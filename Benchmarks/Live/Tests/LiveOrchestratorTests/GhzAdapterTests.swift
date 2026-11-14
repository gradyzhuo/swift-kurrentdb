import Foundation
@testable import LiveBenchCore
@testable import LiveOrchestrator
import Testing

/// A trimmed ghz `--format json` report (the shape ghz 0.121 writes; durations in nanoseconds).
private let report = """
{
  "date": "2026-10-27T02:18:46+08:00",
  "endReason": "normal",
  "options": { "call": "event_store.client.streams.Streams.Append", "rps": 50 },
  "count": 6,
  "total": 2000000000,
  "average": 4000000,
  "rps": 3.0,
  "statusCodeDistribution": { "OK": 3, "DeadlineExceeded": 2, "Unavailable": 1 },
  "errorDistribution": { "rpc error: code = DeadlineExceeded": 2, "rpc error: code = Unavailable": 1 },
  "details": [
    { "timestamp": "2026-10-27T02:18:46.758562+08:00", "latency": 1500000, "error": "", "status": "OK" },
    { "timestamp": "2026-10-27T02:18:46.777226+08:00", "latency": 2499, "error": "", "status": "OK" },
    { "timestamp": "2026-10-27T02:18:46.783419+08:00", "latency": 3000000, "error": "", "status": "OK" },
    { "timestamp": "2026-10-27T02:18:46.788413+08:00", "latency": 5000000000, "error": "rpc error: code = DeadlineExceeded", "status": "DeadlineExceeded" },
    { "timestamp": "2026-10-27T02:18:46.792493+08:00", "latency": 5000000000, "error": "rpc error: code = DeadlineExceeded", "status": "DeadlineExceeded" },
    { "timestamp": "2026-10-27T02:18:46.792493+08:00", "latency": 100000, "error": "rpc error: code = Unavailable", "status": "Unavailable" }
  ]
}
"""

@Suite("ghz adapter")
struct GhzAdapterTests {
    @Test func ghzReportConvertsWithRpcStartTiming() throws {
        let (result, histogram) = try GhzAdapter.convert(report: Data(report.utf8), cellId: "append-latency-300-tls", rate: 50)
        #expect(result.timing == .rpcStart)
        #expect(result.client == "ghz")
        #expect(result.cellId == "append-latency-300-tls" && result.targetRate == 50)
        #expect(result.scheduled == 6)
        #expect(result.succeeded == 3 && result.timedOut == 2 && result.failed == 1 && result.dropped == 0)
        #expect(result.succeeded + result.failed + result.dropped + result.timedOut == result.scheduled)
        #expect(result.measuredSeconds == 2)
        // Successes only, in whole microseconds, at least 1 us.
        #expect(histogram.buckets.reduce(0) { $0 + $1[1] } == 3)
        let h = histogram.histogram()
        #expect(h.min == 2)
        #expect(h.max >= 2999 && h.max <= 3002)
    }

    @Test func reportWithoutDetailsIsRejected() {
        let bare = #"{"count": 3, "total": 1000000000, "statusCodeDistribution": {"OK": 3}}"#
        #expect(throws: GhzAdapter.GhzError.self) { try GhzAdapter.convert(report: Data(bare.utf8), cellId: "c", rate: 1) }
    }

    @Test func emptyRunConvertsToZeroCounts() throws {
        let empty = #"{"count": 0, "total": 0, "details": []}"#
        let (result, histogram) = try GhzAdapter.convert(report: Data(empty.utf8), cellId: "c", rate: 1)
        #expect(result.scheduled == 0 && result.succeeded == 0 && result.measuredSeconds == 0)
        #expect(histogram.buckets.isEmpty)
    }

    @Test func appendConfigUsesThePayloadBytesAndExpandsTheBatch() throws {
        var scenario = EffectiveScenario.fixture(kind: .appendThroughput, eventSize: 1024, rate: 20, measureSeconds: 60)
        scenario.streamPrefix = "bench"
        scenario.category = "bench"
        let template = try Data(contentsOf: ghzDirectory.appendingPathComponent("append.json"))
        let target = GhzTarget(host: "127.0.0.1:2113", caFile: URL(fileURLWithPath: "/work/certs/ca/ca.crt"), authorization: "Basic YWRtaW46Y2hhbmdlaXQ=")
        let data = try GhzAdapter.callConfig(
            template: template, templateDirectory: ghzDirectory, scenario: scenario, warmup: false, target: target,
            seconds: 60, output: URL(fileURLWithPath: "/out/ghz.json")
        )
        let config = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(config["call"] as? String == "event_store.client.streams.Streams.Append")
        #expect(config["rps"] as? Int == 20)
        #expect(config["duration"] as? String == "60000ms")
        #expect(config["timeout"] as? String == "5000ms")
        #expect(config["concurrency"] as? Int == 256)
        #expect(config["connections"] as? Int == 1)
        #expect(config["host"] as? String == "127.0.0.1:2113")
        #expect(config["cacert"] as? String == "/work/certs/ca/ca.crt")
        #expect(config["insecure"] as? Bool != true)
        #expect((config["metadata"] as? [String: String])?["authorization"] == "Basic YWRtaW46Y2hhbmdlaXQ=")
        let imports = try #require(config["import-paths"] as? [String])
        #expect(imports.allSatisfy { $0.hasPrefix("/") })
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: imports[0]).appendingPathComponent(config["proto"] as? String ?? "").path))

        let messages = try #require(config["data"] as? [[String: Any]])
        #expect(messages.count == 1 + 50)
        let options = try #require(messages[0]["options"] as? [String: Any])
        let streamName = try #require((options["stream_identifier"] as? [String: Any])?["stream_name"] as? String)
        #expect(streamName.contains("`bench-%d`") && streamName.contains("100"))
        let proposed = try #require(messages[1]["proposed_message"] as? [String: Any])
        let payload = PayloadFactory(dataSize: 1024, metadataSize: 60, seed: 42)
        #expect(Data(base64Encoded: proposed["data"] as? String ?? "") == payload.data(index: 0))
        #expect(Data(base64Encoded: proposed["custom_metadata"] as? String ?? "") == payload.metadata(index: 0))
        #expect(!String(decoding: data, as: UTF8.self).contains("@@"))
    }

    @Test func rebuildWarmupConfigReadsWarmupStreamsWithoutTLS() throws {
        var scenario = EffectiveScenario.fixture(kind: .rebuild, rate: 5)
        scenario.streamPrefix = "bench"
        scenario.category = "bench"
        scenario.streamLength = 1000
        scenario.rebuildStreams = (0..<100).map { "bench-\($0)" }
        let template = try Data(contentsOf: ghzDirectory.appendingPathComponent("read.json"))
        let target = GhzTarget(host: "127.0.0.1:2113", caFile: nil, authorization: "Basic YWRtaW46Y2hhbmdlaXQ=")
        let data = try GhzAdapter.callConfig(
            template: template, templateDirectory: ghzDirectory, scenario: scenario, warmup: true, target: target,
            seconds: 30, output: URL(fileURLWithPath: "/out/w.json")
        )
        let config = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(config["call"] as? String == "event_store.client.streams.Streams.Read")
        #expect(config["insecure"] as? Bool == true && config["cacert"] == nil)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("`benchw-%d`"))
        let options = try #require((config["data"] as? [String: Any])?["options"] as? [String: Any])
        #expect(options["count"] as? String == "1000")
        #expect(options["resolve_links"] as? Bool == false)
    }

    private var ghzDirectory: URL { livePackageDirectory.appendingPathComponent("drivers/ghz") }
}
