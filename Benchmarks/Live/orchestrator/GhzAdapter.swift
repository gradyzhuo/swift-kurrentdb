import Foundation
import Histogram
import LiveBenchCore

/// Where ghz connects: the server's gRPC endpoint, its CA (nil = plaintext) and the `authorization` header value.
struct GhzTarget: Sendable, Equatable {
    var host: String
    var caFile: URL?
    var authorization: String
}

/// ghz as a transport reference (append and rebuild cells only): builds its per-trial call config from
/// `drivers/ghz/append.json` / `read.json` and converts its JSON report to the driver contract's two files.
///
/// What ghz does differently from the drivers (the report states it; ghz latency is never put in a ratio):
/// - **Timing**: ghz times each call from the RPC start, not from the scheduled send time (`Timing.rpcStart`).
/// - **In-flight cap**: `concurrency` = `inFlightCap` workers. When all are busy ghz waits instead of dropping, so
///   `dropped` is always 0 and the wait is charged to nobody (coordinated omission); a shortfall shows as fewer
///   `scheduled` calls than `rate * measure`.
/// - **Deadline**: the call `timeout` is the deadline from the RPC start; an expired call is `DeadlineExceeded` and
///   counted as a timeout. `duration-stop: wait` lets calls in flight at the end finish (bounded by the timeout), the
///   closest ghz has to the drain.
/// - **Stream choice**: round robin, `<prefix>-<requestNumber % streamCount>` (ghz templates cannot run the seeded
///   splitmix64 draw); the set of streams is the same.
/// - **Payload**: every event carries the bytes of event index 0 from `PayloadFactory` (exact `eventSize` data and
///   `metadataSize` metadata, same filler), instead of index `k`; event type `BenchEvent`, content type JSON, a fresh
///   UUID per event, expected revision any, the same batch size (one options message plus `batchSize` events).
/// - **Rebuild**: reads the whole stream (`count = streamLength`, links not resolved) without decoding any event, and
///   checks no counts; `validation` holds successful calls on both sides, informational only.
/// - **Process usage**: ghz's CPU and RSS are not measured (0 in the result).
/// - **Warmup**: a separate ghz run against the warmup streams (`<prefix>w-*`) before the measured run.
enum GhzAdapter {
    enum GhzError: Error, CustomStringConvertible {
        case malformedReport(String)
        case missingDetails(count: Int)
        case malformedTemplate(String)

        var description: String {
            switch self {
            case let .malformedReport(problem): "ghz report: \(problem)"
            case let .missingDetails(count): "ghz report has no per-call details for its \(count) calls (run with --format json)"
            case let .malformedTemplate(problem): "ghz call config template: \(problem)"
            }
        }
    }

    private struct Report: Decodable {
        var count: Int
        /// Wall time of the run, nanoseconds.
        var total: Int64
        var details: [Detail]?

        struct Detail: Decodable {
            /// Nanoseconds from the RPC start.
            var latency: Int64
            var status: String
        }
    }

    /// Converts a ghz `--format json` report into a `TrialResult` (`client` "ghz", `timing` `.rpcStart`) and a
    /// histogram of the successful calls in whole microseconds. `OK` is a success, `DeadlineExceeded` a timeout,
    /// any other status a failure; nothing is dropped.
    static func convert(report data: Data, cellId: String, rate: Double) throws -> (TrialResult, HistogramFile) {
        let report: Report
        do {
            report = try JSONDecoder().decode(Report.self, from: data)
        } catch {
            throw GhzError.malformedReport("\(error)")
        }
        let details = report.details ?? []
        guard details.count == report.count else {
            if details.isEmpty, report.count > 0 { throw GhzError.missingDetails(count: report.count) }
            throw GhzError.malformedReport("\(details.count) details for \(report.count) calls")
        }
        var histogram = Histogram<UInt64>(lowestDiscernibleValue: 1, highestTrackableValue: 60_000_000, numberOfSignificantValueDigits: .three)
        var succeeded = 0, timedOut = 0, failed = 0
        for detail in details {
            switch detail.status {
            case "OK":
                succeeded += 1
                let micros = UInt64(max(detail.latency, 0) / 1000)
                _ = histogram.record(min(max(micros, 1), 60_000_000))
            case "DeadlineExceeded":
                timedOut += 1
            default:
                failed += 1
            }
        }
        let result = TrialResult(
            client: "ghz", cellId: cellId, targetRate: rate, timing: .rpcStart,
            scheduled: report.count, succeeded: succeeded, failed: failed, dropped: 0, timedOut: timedOut,
            measuredSeconds: Double(max(report.total, 0)) / 1e9, cpuUserSeconds: 0, cpuSystemSeconds: 0, maxRssBytes: 0,
            validation: Validation(expectedEvents: succeeded, receivedEvents: succeeded, payloadSizesOk: true)
        )
        return (result, HistogramFile(histogram))
    }

    /// The ghz `--config` for one run of `scenario`: the committed `template` with its placeholders filled
    /// (`@@STREAM_PREFIX@@`, `@@STREAM_COUNT@@`, `@@STREAM_LENGTH@@`, `@@DATA@@`, `@@METADATA@@`), its `import-paths`
    /// made absolute against `templateDirectory`, an Append's event message repeated `batchSize` times, and the
    /// run settings (target, TLS, auth header, rate, duration, deadline, concurrency, output) set.
    static func callConfig(
        template: Data, templateDirectory: URL, scenario: EffectiveScenario, warmup: Bool, target: GhzTarget,
        seconds: Double, output: URL
    ) throws -> Data {
        let payloads = PayloadFactory(dataSize: scenario.eventSize, metadataSize: scenario.metadataSize, seed: scenario.seed)
        let streamCount = scenario.kind == .rebuild ? (scenario.rebuildStreams?.count ?? 0) : scenario.streamCount
        let replacements = [
            "@@STREAM_PREFIX@@": scenario.streamPrefix + (warmup ? "w" : ""),
            "@@STREAM_COUNT@@": "\(max(streamCount, 1))",
            "@@STREAM_LENGTH@@": "\(scenario.streamLength ?? 0)",
            "@@DATA@@": payloads.data(index: 0).base64EncodedString(),
            "@@METADATA@@": payloads.metadata(index: 0).base64EncodedString(),
        ]
        guard var config = try JSONSerialization.jsonObject(with: template) as? [String: Any] else {
            throw GhzError.malformedTemplate("not a JSON object")
        }
        config = try substitute(config, replacements) as? [String: Any] ?? config

        if let call = config["call"] as? String, call.hasSuffix(".Append") {
            guard let messages = config["data"] as? [Any], messages.count == 2 else {
                throw GhzError.malformedTemplate("an Append template's data must be [options, proposed_message]")
            }
            config["data"] = [messages[0]] + Array(repeating: messages[1], count: max(scenario.batchSize, 1))
        }
        if let paths = config["import-paths"] as? [String] {
            config["import-paths"] = paths.map { templateDirectory.appendingPathComponent($0).standardizedFileURL.path }
        }
        config["host"] = target.host
        if let caFile = target.caFile {
            config["cacert"] = caFile.path
            config.removeValue(forKey: "insecure")
        } else {
            config["insecure"] = true
        }
        config["metadata"] = ["authorization": target.authorization]
        config["rps"] = max(Int(scenario.rate.rounded()), 1)
        config["duration"] = "\(Int((seconds * 1000).rounded()))ms"
        config["timeout"] = "\(scenario.deadlineMillis)ms"
        config["concurrency"] = scenario.inFlightCap
        config["connections"] = 1
        config["format"] = "json"
        config["output"] = output.path
        return try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
    }

    private static func substitute(_ value: Any, _ replacements: [String: String]) throws -> Any {
        switch value {
        case let text as String:
            return replacements.reduce(text) { $0.replacingOccurrences(of: $1.key, with: $1.value) }
        case let array as [Any]:
            return try array.map { try substitute($0, replacements) }
        case let object as [String: Any]:
            return try object.mapValues { try substitute($0, replacements) }
        default:
            return value
        }
    }
}
