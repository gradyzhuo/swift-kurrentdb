import Foundation
@testable import LiveBenchCore
import Testing

/// The Swift driver against a real, throwaway KurrentDB container. Run with `LIVE_BENCH_DOCKER=1`.
@Suite("Swift driver (live)", .serialized, .liveServer)
struct SwiftDriverLiveTests {
    @Test(.enabled(if: docker))
    func appendLatencyAtLowRateProducesSustainedResult() async throws {
        let run = try await runDriverDetailed(.swift, scenario: .fixture(kind: .appendLatency, rate: 50, measureSeconds: 3))
        let result = run.result
        #expect(result.client == "swift")
        #expect(result.timing == .scheduled)
        #expect(result.succeeded == result.scheduled && result.scheduled == 150)
        #expect(result.validation == Validation(expectedEvents: 150, receivedEvents: 150, payloadSizesOk: true))
        #expect(run.histogram.buckets.reduce(0) { $0 + $1[1] } == UInt64(result.succeeded))
        #expect(result.cpuUserSeconds > 0)
        #expect(result.maxRssBytes > 1_000_000)
        #expect(result.uniqueDeliveries == nil && result.catchUpSeconds == nil)
    }

    @Test(.enabled(if: docker))
    func appendThroughputAppendsWholeBatches() async throws {
        let result = try await runDriver(.swift, scenario: .fixture(kind: .appendThroughput, rate: 20, measureSeconds: 2))
        #expect(result.succeeded == result.scheduled && result.scheduled == 40)
        #expect(result.validation == Validation(expectedEvents: 40 * 50, receivedEvents: 40 * 50, payloadSizesOk: true))
    }

    @Test(.enabled(if: docker))
    func rebuildValidatesCountsAndSizes() async throws {
        var scenario = EffectiveScenario.fixture(kind: .rebuild, eventSize: 300, rate: 20, measureSeconds: 2)
        scenario.rebuildStreams = (0..<3).map { "bench-fixture-\($0)" }
        scenario.streamLength = 10
        let result = try await runDriver(.swift, scenario: scenario)
        #expect(result.succeeded == result.scheduled && result.scheduled == 40)
        #expect(result.validation.expectedEvents == 40 * 10)
        #expect(result.validation.receivedEvents == result.validation.expectedEvents)
        #expect(result.validation.payloadSizesOk)
    }

    @Test(.enabled(if: docker))
    func persistentSubscriptionDeliversEveryEventOnce() async throws {
        let run = try await runDriverDetailed(.swift, scenario: .fixture(kind: .persistentSubscription, rate: 50, measureSeconds: 2))
        let result = run.result
        #expect(result.succeeded == result.scheduled && result.scheduled == 100, "\(run.log)")
        #expect(result.uniqueDeliveries == 100)
        #expect(result.redeliveries == 0)
        #expect(result.ackEnqueued == 100)
        #expect(result.validation == Validation(expectedEvents: 100, receivedEvents: 100, payloadSizesOk: true))
    }

    @Test(.enabled(if: docker))
    func persistentSubscriptionWithSeveralConsumersSharesTheGroup() async throws {
        let result = try await runDriver(.swift, scenario: .fixture(kind: .persistentSubscription, rate: 50, measureSeconds: 2, consumers: 3))
        #expect(result.succeeded == result.scheduled && result.scheduled == 100)
        #expect(result.uniqueDeliveries == 100)
        #expect(result.ackEnqueued == 100)
    }

    @Test(.enabled(if: docker))
    func catchUpResolvesLinksSoPayloadSizesMatch() async throws {
        let run = try await runDriverDetailed(.swift, scenario: .fixture(kind: .catchUp, eventSize: 1024, rate: 50, measureSeconds: 2))
        let result = run.result
        #expect(result.validation.payloadSizesOk) // false if links were not resolved: link events carry "<n>@<stream>"
        #expect(try #require(result.catchUpSeconds) > 0)
        #expect(result.succeeded == result.scheduled && result.scheduled == 100, "\(run.log)")
        #expect(result.uniqueDeliveries == 100)
        // Sums over both phases: the 1,000-event corpus plus the live events.
        #expect(result.validation.expectedEvents == 1000 + 100)
        #expect(result.validation.receivedEvents == 1000 + 100)
    }

    @Test(.enabled(if: docker))
    func versionReportsTheRepositoryCommit() async throws {
        let version = try await driverVersion(.swift)
        let head = try runTool("git", ["-C", livePackageDirectory.path, "rev-parse", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(version.client == "swift")
        #expect(version.clientVersion == (ProcessInfo.processInfo.environment["LIVE_BENCH_SDK_COMMIT"] ?? head))
        #expect(version.runtime.hasPrefix("swift 6."))
    }
}
