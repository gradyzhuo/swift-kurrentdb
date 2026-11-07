//
//  SubscriptionMessagesLiveTests.swift
//  swift-kurrentdb
//
//  `Streams.Subscription.messages`: the server's notifications (caught up, fell behind,
//  checkpoints) delivered next to the events. Requires the local TLS cluster.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Subscription messages", .serialized, .timeLimit(.minutes(3)))
struct SubscriptionMessagesLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    static func label(_ message: Streams<SpecifiedStream>.Subscription.Message) -> String {
        switch message {
        case let .event(readEvent): return readEvent.record.eventType
        case .caughtUp: return "caughtUp"
        case .fellBehind: return "fellBehind"
        case .checkpoint: return "checkpoint"
        @unknown default:
            Issue.record("unknown subscription message")
            return "unknown"
        }
    }

    @Test("A subscription from the start delivers the stored events, then caughtUp")
    func testCaughtUpFollowsTheStoredEvents() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        try await client.streams(specified: streamName).append(events: [
            EventData(eventType: "Messages-A", data: Data(), contentType: .json),
            EventData(eventType: "Messages-B", data: Data(), contentType: .json),
        ]) { $0.expectedRevision = .any }

        let subscription = try await client.streams(specified: streamName).subscribe { $0.revision = .start }
        var caughtUp: Streams<SpecifiedStream>.Subscription.CaughtUp?
        var seen: [String] = []
        for try await message in subscription.messages {
            seen.append(Self.label(message))
            if case let .caughtUp(payload) = message { caughtUp = payload; break }
        }
        subscription.cancel()
        #expect(seen == ["Messages-A", "Messages-B", "caughtUp"])
        #expect(caughtUp?.timestamp != nil)      // every CI image sends it (payloads since 24.10.5; 24.10 EE is 24.10.16)
        #expect(caughtUp?.revision == 1)         // the last delivered event's number, two events appended
    }

    @Test("A live event arrives after caughtUp")
    func testEventsKeepArrivingAfterCaughtUp() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        let subscription = try await client.streams(specified: streamName).subscribe()
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Messages-Live", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }

        var seen: [String] = []
        var caughtUp: Streams<SpecifiedStream>.Subscription.CaughtUp?
        for try await message in subscription.messages {
            seen.append(Self.label(message))
            if case let .caughtUp(payload) = message, caughtUp == nil { caughtUp = payload }
            if case .event = message { break }
        }
        subscription.cancel()
        #expect(seen.last == "Messages-Live")
        #expect(seen.dropLast().allSatisfy { $0 == "caughtUp" })
        // Subscribed at `.end` of a stream with no events: nothing to resume after yet.
        #expect(caughtUp?.timestamp != nil)
        #expect(caughtUp?.revision == nil)
    }

    @Test("A filtered $all subscription reports a checkpoint while scanning events the filter rejects")
    func testFilteredAllSubscriptionReportsCheckpoints() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        // The first checkpoint is the start position, so three need two checkpoint intervals (32 × 1)
        // of events the filter rejects; 100 leave room even on a fresh node with few system events.
        try await client.streams(specified: UUID().uuidString).append(
            events: (0 ..< 100).map { _ in EventData(eventType: "Messages-Noise", data: Data(), contentType: .json) }
        ) { $0.expectedRevision = .any }

        let subscription = try await client.allStreams.subscribe {
            $0.position = .start
            $0.filter = .onStreamName(prefixes: "no-such-stream-\(UUID().uuidString)").max(32).checkpointIntervalMultiplier(1)
        }
        // The first checkpoint is the start position itself; the next ones move forward.
        var checkpoints: [Streams<AllStreamsTarget>.Subscription.Checkpoint] = []
        for try await message in subscription.messages {
            if case let .checkpoint(checkpoint) = message { checkpoints.append(checkpoint) }
            if case .caughtUp = message { break }
            if checkpoints.count == 3 { break }
        }
        subscription.cancel()
        let commits = checkpoints.map(\.position.commit)
        #expect(checkpoints.count == 3, "checkpoints before caughtUp: \(commits)")
        #expect(commits == commits.sorted() && commits.last ?? 0 > 0)
        #expect(checkpoints.allSatisfy { $0.timestamp != nil })
    }

    @Test("A $all subscription from .end reports its position in the first caughtUp")
    func testAllSubscriptionFromEndCaughtUpHasPosition() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        let subscription = try await client.allStreams.subscribe { $0.position = .end }
        var caughtUp: Streams<AllStreamsTarget>.Subscription.CaughtUp?
        for try await message in subscription.messages {
            if case let .caughtUp(payload) = message { caughtUp = payload; break }
        }
        subscription.cancel()
        // `.end` resolves to the log's last indexed position at once.
        #expect(caughtUp?.position != nil, "\(String(describing: caughtUp))")
        #expect(caughtUp?.timestamp != nil)
    }

    @Test("A filtered $all subscription from .start reports a position once it has caught up")
    func testFilteredAllSubscriptionCaughtUpHasPosition() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        let subscription = try await client.allStreams.subscribe {
            $0.position = .start
            $0.filter = .onStreamName(prefixes: "no-such-stream-\(UUID().uuidString)").max(32).checkpointIntervalMultiplier(1)
        }
        // Scans the whole log; the suite's time limit bounds the loop.
        var lastCheckpoint: Streams<AllStreamsTarget>.Subscription.Checkpoint?
        var caughtUp: Streams<AllStreamsTarget>.Subscription.CaughtUp?
        for try await message in subscription.messages {
            if case let .checkpoint(checkpoint) = message { lastCheckpoint = checkpoint }
            if case let .caughtUp(payload) = message { caughtUp = payload; break }
        }
        subscription.cancel()
        let position = try #require(caughtUp?.position, "\(String(describing: caughtUp))")
        #expect(caughtUp?.timestamp != nil)
        if let lastCheckpoint {
            #expect(position.commit >= lastCheckpoint.position.commit)
        }
    }

    @Test("A stream subscription from .start of a stream with no events has no revision until an event arrives")
    func testCaughtUpRevisionFollowsTheFirstEvent() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        let subscription = try await client.streams(specified: streamName).subscribe { $0.revision = .start }
        var iterator = subscription.messages.makeAsyncIterator()
        var caughtUp: Streams<SpecifiedStream>.Subscription.CaughtUp?
        while let message = try await iterator.next() {
            if case let .caughtUp(payload) = message { caughtUp = payload; break }
        }
        #expect(caughtUp != nil)
        #expect(caughtUp?.revision == nil)
        #expect(caughtUp?.timestamp != nil)

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Messages-First", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }
        // A caughtUp after the event is not guaranteed, so stop at the event: the "after events"
        // half of the rule is testCaughtUpFollowsTheStoredEvents.
        var revision: UInt64?
        while let message = try await iterator.next() {
            if case let .event(readEvent) = message { revision = readEvent.record.revision; break }
        }
        subscription.cancel()
        #expect(revision == 0)
    }

    /// KurrentDB 26.2.2 is the first server that sends `fellBehind` (to a client declaring
    /// compatibility 2); older ones switch back to catch-up silently. CI sets the flag on 26.2.
    @Test("A consumer that stalls while the stream is written to is told it fell behind, then that it caught up again",
          .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_SUPPORTS_FELL_BEHIND"] == "true"))
    func testFellBehindWhenTheConsumerStalls() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        let subscription = try await client.streams(specified: streamName).subscribe()
        var iterator = subscription.messages.makeAsyncIterator()
        while let message = try await iterator.next() {
            if case .caughtUp = message { break }
        }

        // Nobody reads while more is written than the server's live buffer holds: the hand-off
        // suspends the producer, flow control stops the server, and its live buffer overflows,
        // once per batch here.
        let payload = Data(repeating: 0x61, count: 4096)
        let batches = 10, perBatch = 200
        for _ in 0 ..< batches {
            try await client.streams(specified: streamName).append(
                events: (0 ..< perBatch).map { _ in EventData(eventType: "Messages-Flood", data: payload, contentType: .json) }
            ) { $0.expectedRevision = .any }
        }

        var notifications: [String] = []
        var events = 0
        var behind = false
        var allTimestamped = true
        var lastCaughtUp: Streams<SpecifiedStream>.Subscription.CaughtUp?
        var eventsBeforeLastCaughtUp = 0
        while let message = try await iterator.next() {
            switch message {
            case .event: events += 1
            case let .fellBehind(fellBehind):
                behind = true; notifications.append("fellBehind")
                allTimestamped = allTimestamped && fellBehind.timestamp != nil
            case let .caughtUp(caughtUp):
                behind = false; notifications.append("caughtUp")
                allTimestamped = allTimestamped && caughtUp.timestamp != nil
                lastCaughtUp = caughtUp; eventsBeforeLastCaughtUp = events
            case .checkpoint: notifications.append("checkpoint")
            @unknown default: Issue.record("unknown subscription message")
            }
            // The last events may arrive live after the final caughtUp, so stop on the count.
            if events == batches * perBatch, !behind { break }
        }
        subscription.cancel()
        // Every return to catch-up is announced, and every catch-up ends with caughtUp.
        #expect(notifications.first == "fellBehind", "\(notifications)")
        #expect(notifications == Array(repeating: ["fellBehind", "caughtUp"], count: notifications.count / 2).flatMap { $0 }, "\(notifications)")
        #expect(events == batches * perBatch)   // the switch to catch-up neither drops nor repeats an event
        #expect(allTimestamped)
        // revision is the last event delivered before that caughtUp; events after it may arrive live.
        let caughtUpAfter = try #require(lastCaughtUp, "\(notifications)")
        #expect(caughtUpAfter.revision.map { $0 + 1 } == UInt64(eventsBeforeLastCaughtUp), "\(caughtUpAfter) after \(eventsBeforeLastCaughtUp) events")
    }

    @Test("Tombstoning the stream ends messages with resourceDeleted too")
    func testTombstoneEndsMessagesWithResourceDeleted() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Messages-Before", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }
        let subscription = try await client.streams(specified: streamName).subscribe { $0.revision = .start }
        try await client.streams(specified: streamName).tombstone()

        var seen: [String] = []
        await #expect(throws: KurrentError.resourceDeleted(resource: streamName)) {
            for try await message in subscription.messages {
                seen.append(Self.label(message))
            }
        }
        #expect(seen.contains("Messages-Before"))
        #expect(!seen.contains("$streamDeleted"))
    }

    @Test("events outlives the subscription value it was taken from")
    func testEventsOutlivesTheSubscriptionValue() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }

        // Keep only the stream: the subscription value, `messages` with it, is released here.
        let events = try await client.streams(specified: streamName).subscribe().events
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Messages-Kept", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }

        var seen: [String] = []
        for try await event in events {
            seen.append(event.record.eventType)
            break
        }
        #expect(seen == ["Messages-Kept"])
    }
}
