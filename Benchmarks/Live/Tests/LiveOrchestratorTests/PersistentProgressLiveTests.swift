import Foundation
import KurrentDB
@testable import LiveBenchCore
@testable import LiveOrchestrator
import Testing

/// Which `SubscriptionInfo` field is the server's acknowledged progress, against a real throwaway server.
/// Run with `LIVE_BENCH_DOCKER=1`.
@Suite("Persistent subscription progress (live)", .serialized, .liveServer)
struct PersistentProgressLiveTests {
    /// The probe: deliver 100 events, ack none, then ack all, and see which fields move when.
    @Test(.enabled(if: docker))
    func checkpointAdvancesOnlyOnAck() async throws {
        let server = try #require(LiveServer.current)
        let client = KurrentDBClient(settings: try ClientSettings.parse(connectionString: server.connectionString))
        defer { try? client.shutdown() }
        try await enableByCategory(client)

        let category = "probe" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
        let stream = "$ce-\(category)"
        let group = "g0-250-probe"
        try await PersistentProgress.createGroup(client: client, stream: stream, group: group)

        let factory = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 42)
        let events = (0..<100).map {
            EventData(eventType: "BenchEvent", data: factory.data(index: $0), contentType: .json, customMetadata: factory.metadata(index: $0))
        }
        for (n, chunk) in stride(from: 0, to: 100, by: 10).enumerated() {
            _ = try await client.streams(specified: "\(category)-\(n)").append(events: Array(events[chunk..<chunk + 10]))
        }

        let subscriptions = client.persistentSubscriptions(stream: stream, group: group)
        let unacked: PersistentSubscription.SubscriptionInfo
        let acked: PersistentSubscription.SubscriptionInfo
        do {
            // Scoped: the subscription's connection closes once nothing references it.
            let subscription = try await subscriptions.subscribe()
            var received: [ReadEvent] = []
            for try await result in subscription.events {
                received.append(result.event)
                if received.count == 100 { break }
            }
            #expect(received.count == 100)

            try await Task.sleep(for: .seconds(5))
            unacked = try await subscriptions.getInfo()
            print("probe unacked: \(describe(unacked))")

            try await subscription.ack(readEvents: received)
            try await Task.sleep(for: .milliseconds(Int(unacked.checkPointAfterMilliseconds) + 2000))
            acked = try await subscriptions.getInfo()
            print("probe acked:   \(describe(acked))")
        }
        try await Task.sleep(for: .seconds(2))
        let disconnected = try await subscriptions.getInfo()
        print("probe disconnected: \(describe(disconnected))")

        // Delivered but not acked: delivery counters already show all 100, the checkpoint does not.
        #expect(unacked.totalItems == 100)
        #expect(PersistentProgress.acknowledgedEvents(unacked) == 0)
        // Acked: the checkpoint covers all 100 events (revisions 0...99 of the `$ce-` stream).
        #expect(PersistentProgress.acknowledgedEvents(acked) == 100)
        #expect(PersistentProgress.acknowledgedEvents(disconnected) == 100)
        // The window-end read is the same field, read once.
        #expect(try await PersistentProgress.readOnce(client: client, stream: stream, group: group) == 100)
    }

    /// The monitor's projection gate: the target is the last event written to the trial's streams, and the gate
    /// reports whether `$by_category` processed it within the bound.
    @Test(.enabled(if: docker))
    func projectionCatchUpTargetsTheLastWrittenEvent() async throws {
        let server = try #require(LiveServer.current)
        let client = KurrentDBClient(settings: try ClientSettings.parse(connectionString: server.connectionString))
        defer { try? client.shutdown() }
        try await enableByCategory(client)
        let category = "probe" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
        let factory = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 42)
        func append(_ stream: String, _ count: Int) async throws -> LogPosition {
            let response = try await client.streams(specified: stream).append(events: (0..<count).map {
                EventData(eventType: "BenchEvent", data: factory.data(index: $0), contentType: .json, customMetadata: factory.metadata(index: $0))
            })
            let position = try #require(response.position)
            return LogPosition(commit: position.commit, prepare: position.prepare)
        }
        _ = try await append("\(category)-0", 10)
        let last = try await append("\(category)-1", 10)
        // Another category written later is not the trial's.
        _ = try await append("other\(category)-0", 5)
        #expect(try await lastWrittenPosition(client, streamPrefix: "\(category)-") == last)
        #expect(try await lastWrittenPosition(client, streamPrefix: "nothing\(category)-") == .zero)

        let caughtUp = await byCategoryCatchUp(client: client, streamPrefix: "\(category)-", within: .seconds(5))
        print("probe catch-up: \(caughtUp)")
        guard case let .caughtUp(seconds) = caughtUp else {
            Issue.record("expected caught up, got \(caughtUp)")
            return
        }
        #expect(seconds >= 0 && seconds <= 5)

        // A stopped projection never reaches newer events: not caught up (the gate fails), not unreadable.
        try await client.projections(system: .byCategory).disable()
        do {
            try await Task.sleep(for: .seconds(1))
            _ = try await append("\(category)-2", 10)
            #expect(await byCategoryCatchUp(client: client, streamPrefix: "\(category)-", within: .seconds(2)) == .notCaughtUp)
        }
        try await enableByCategory(client)
    }

    /// `read(...)` as the orchestrator calls it after a trial: polls until the checkpoint reaches `expected`.
    @Test(.enabled(if: docker))
    func readWaitsForTheCheckpointToReachWrittenEvents() async throws {
        let server = try #require(LiveServer.current)
        let client = KurrentDBClient(settings: try ClientSettings.parse(connectionString: server.connectionString))
        defer { try? client.shutdown() }
        try await enableByCategory(client)
        let category = "probe" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(10).lowercased()
        let stream = "$ce-\(category)"
        try await PersistentProgress.createGroup(client: client, stream: stream, group: "g")
        let factory = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 42)
        _ = try await client.streams(specified: "\(category)-0").append(events: (0..<20).map {
            EventData(eventType: "BenchEvent", data: factory.data(index: $0), contentType: .json, customMetadata: factory.metadata(index: $0))
        })
        // The consumer stays connected while `read` polls: acks still in flight when a consumer disconnects are lost
        // (seen once: closing right after the 20th ack left the checkpoint at 16), the events go back to be retried.
        let subscription = try await client.persistentSubscriptions(stream: stream, group: "g").subscribe()
        var seen = 0
        for try await result in subscription.events {
            try await subscription.ack(readEvents: result.event)
            seen += 1
            if seen == 20 { break }
        }
        let clock = ContinuousClock()
        let started = clock.now
        let progress = try await PersistentProgress.read(client: client, stream: stream, group: "g", expected: 20, timeout: .seconds(15))
        print("probe read: \(progress) after \(started.duration(to: clock.now))")
        #expect(progress == 20)
        // Still under the bound the orchestrator uses.
        #expect(started.duration(to: clock.now) < PersistentProgress.readTimeout)
        withExtendedLifetime(subscription) {}
    }

    private func describe(_ info: PersistentSubscription.SubscriptionInfo) -> String {
        "totalItems=\(info.totalItems) lastCheckpointedEventPosition='\(info.lastCheckpointedEventPosition)' "
            + "lastKnownEventPosition='\(info.lastKnownEventPosition)' outstanding=\(info.outstandingMessageCount) "
            + "inFlight=\(info.totalInFlightMessages) connections=\(info.connections.map { "\($0.totalItems)/\($0.inFlightMessages)" }) "
            + "checkpointAfterMs=\(info.checkPointAfterMilliseconds) min=\(info.minCheckPointCount) max=\(info.maxCheckPointCount)"
    }
}
