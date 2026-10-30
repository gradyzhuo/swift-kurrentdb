import Foundation
import KurrentDB
@testable import LiveBenchCore
import Testing

/// Every driver against the same throwaway KurrentDB container, checked against `docs/driver-contract.md`. The same
/// assertions run for each client, so a driver that diverges from the contract fails here, not in a published ratio.
/// Run with `LIVE_BENCH_DOCKER=1` (the .NET driver also needs `dotnet` 8 on `PATH`).
@Suite("Driver contract conformance (live)", .serialized, .liveServer)
struct ContractConformanceLiveTests {
    @Test(.enabled(if: docker), arguments: [Client.swift, .dotnet])
    func everyKindProducesAValidatedResult(client: Client) async throws {
        for kind in ScenarioKind.allCases {
            let run = try await runDriverDetailed(client, scenario: .fixture(kind: kind, rate: 20, measureSeconds: 3))
            let r = run.result
            let context = "\(client) \(kind): \(run.log)"
            let p50 = r.succeeded > 0 ? run.histogram.histogram().valueAtPercentile(50) : 0
            print("conformance \(client) \(kind.rawValue): \(r.succeeded)/\(r.scheduled) ok, p50 \(p50) µs, validation \(r.validation), deliveries \(r.uniqueDeliveries.map(String.init) ?? "-"), acks \(r.ackEnqueued.map(String.init) ?? "-"), catch-up \(r.catchUpSeconds.map { String(format: "%.2f s", $0) } ?? "-"), cpu \(String(format: "%.2f", r.cpuUserSeconds + r.cpuSystemSeconds)) s, rss \(r.maxRssBytes / 1_000_000) MB")
            #expect(r.client == client.description, "\(context)")
            #expect(r.cellId == run.scenario.cellId)
            #expect(r.targetRate == 20)
            #expect(r.timing == .scheduled)
            #expect(r.measuredSeconds == 3)
            #expect(r.scheduled == 60, "\(context)")
            #expect(r.succeeded + r.failed + r.dropped + r.timedOut == r.scheduled)
            #expect(r.succeeded == r.scheduled, "\(context)")
            #expect(run.histogram.unit == "us")
            #expect(run.histogram.buckets.reduce(0) { $0 + $1[1] } == UInt64(r.succeeded))
            #expect(run.histogram.buckets.allSatisfy { $0.count == 2 && $0[0] >= 1 && $0[0] <= 60_000_000 })
            #expect(run.histogram.buckets.map { $0[0] } == run.histogram.buckets.map { $0[0] }.sorted())
            #expect(r.validation.receivedEvents == r.validation.expectedEvents, "\(context)")
            #expect(r.validation.payloadSizesOk, "\(context)")
            #expect(r.cpuUserSeconds + r.cpuSystemSeconds > 0)
            #expect(r.maxRssBytes > 1_000_000)
            // The measure-start marker: the exact line, once.
            #expect(run.stderr.split(whereSeparator: \.isNewline).filter { $0 == "LIVE_BENCH_MEASURE_START" }.count == 1, "\(context)")

            switch kind {
            case .appendLatency, .appendThroughput:
                #expect(r.validation.expectedEvents == r.succeeded * run.scenario.batchSize)
                #expect(r.uniqueDeliveries == nil && r.redeliveries == nil && r.ackEnqueued == nil && r.catchUpSeconds == nil)
            case .rebuild:
                #expect(r.validation.expectedEvents == r.succeeded * (run.scenario.streamLength ?? 0))
                #expect(r.uniqueDeliveries == nil && r.catchUpSeconds == nil)
            case .persistentSubscription:
                #expect(r.uniqueDeliveries == r.succeeded, "\(context)")
                #expect(r.redeliveries == 0)
                #expect(r.ackEnqueued == r.succeeded, "\(context)")
                #expect(r.catchUpSeconds == nil)
            case .catchUp:
                let corpus = run.scenario.catchUpExpectedEvents ?? 0
                #expect(try #require(r.catchUpSeconds) > 0)
                #expect(r.uniqueDeliveries == r.succeeded)
                #expect(r.validation.expectedEvents == corpus + r.succeeded)
                #expect(r.ackEnqueued == nil)
            }
        }
    }

    /// Several consumers share the group (RoundRobin): every event is delivered and acked once across them.
    @Test(.enabled(if: docker), arguments: [Client.swift, .dotnet])
    func persistentSubscriptionWithSeveralConsumersSharesTheGroup(client: Client) async throws {
        let run = try await runDriverDetailed(client, scenario: .fixture(kind: .persistentSubscription, rate: 50, measureSeconds: 2, consumers: 3))
        let r = run.result
        #expect(r.succeeded == r.scheduled && r.scheduled == 100, "\(client): \(run.log)")
        #expect(r.uniqueDeliveries == 100)
        #expect(r.redeliveries == 0)
        #expect(r.ackEnqueued == 100)
    }

    /// Byte-for-byte payloads, event type and content type, and the seeded stream picks: every client writes the same
    /// events to the same streams.
    @Test(.enabled(if: docker), arguments: [Client.swift, .dotnet])
    func appendedEventsFollowThePayloadAndStreamRules(client: Client) async throws {
        var scenario = EffectiveScenario.fixture(kind: .appendThroughput, rate: 5, measureSeconds: 1)
        scenario.warmupSeconds = 0
        scenario.streamCount = 7
        let run = try await runDriverDetailed(client, scenario: scenario)
        #expect(run.result.succeeded == 5, "\(run.log)")
        let s = run.scenario
        let factory = PayloadFactory(dataSize: s.eventSize, metadataSize: s.metadataSize, seed: s.seed)

        let server = try #require(LiveServer.current)
        let sdk = KurrentDBClient(settings: try ClientSettings.parse(connectionString: server.connectionString))
        defer { try? sdk.shutdown() }
        var expectedByStream: [String: [Int]] = [:]
        for i in 0..<5 {
            let stream = "\(s.streamPrefix)-\(SeededDraw.pick(seed: s.seed, index: i, count: s.streamCount))"
            expectedByStream[stream, default: []] += Array(i * s.batchSize ..< (i + 1) * s.batchSize)
        }
        var checked = 0
        for (stream, indices) in expectedByStream {
            var seen: [Int] = []
            for try await response in sdk.streams(specified: stream).read().lazy {
                let record = try response.event.record
                let k = try #require(DeliveryIndex.parse(record.data))
                #expect(record.eventType == "BenchEvent")
                #expect(record.contentType == .json)
                #expect(record.data == factory.data(index: k), "\(client) event \(k)")
                #expect(record.customMetadata == factory.metadata(index: k), "\(client) metadata \(k)")
                seen.append(k)
                checked += 1
            }
            #expect(seen.sorted() == indices.sorted(), "\(client) \(stream)")
        }
        #expect(checked == 5 * s.batchSize)
    }

    @Test(.enabled(if: docker), arguments: [Client.swift, .dotnet])
    func versionReportsExactClientVersion(client: Client) async throws {
        let version = try await driverVersion(client)
        #expect(version.client == client.description)
        switch client {
        case .swift:
            let head = try runTool("git", ["-C", livePackageDirectory.path, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(version.clientVersion == (ProcessInfo.processInfo.environment["LIVE_BENCH_SDK_COMMIT"] ?? head))
            #expect(version.runtime.hasPrefix("swift 6."))
        case .dotnet:
            #expect(version.clientVersion == (try pinnedDotNetClientVersion()))
            #expect(version.runtime.hasPrefix(".NET 8."))
        }
    }
}

/// `KurrentDB.Client`'s exact version: the csproj pin, which must also be what `packages.lock.json` resolved.
private func pinnedDotNetClientVersion() throws -> String {
    let project = try String(contentsOf: DotNetDriverBuild.projectDirectory.appendingPathComponent("LiveDriver.DotNet.csproj"), encoding: .utf8)
    guard let pin = project.firstMatch(of: /<KurrentDBClientVersion>([^<]+)<\/KurrentDBClientVersion>/)?.1 else {
        throw HarnessError("no KurrentDBClientVersion in the csproj")
    }
    struct LockFile: Decodable {
        struct Package: Decodable { var resolved: String }
        var dependencies: [String: [String: Package]]
    }
    let lock = try JSONDecoder().decode(LockFile.self, from: Data(contentsOf: DotNetDriverBuild.projectDirectory.appendingPathComponent("packages.lock.json")))
    let resolved = lock.dependencies.values.compactMap { $0["KurrentDB.Client"]?.resolved }
    guard resolved == [String(pin)] else { throw HarnessError("packages.lock.json resolved \(resolved), csproj pins \(pin)") }
    return String(pin)
}

/// `k` from event data that starts with `{"i":k,`.
private enum DeliveryIndex {
    static func parse(_ data: Data) -> Int? {
        guard let text = String(data: data.prefix(32), encoding: .utf8), text.hasPrefix(#"{"i":"#) else { return nil }
        return Int(text.dropFirst(5).prefix { $0.isNumber })
    }
}
