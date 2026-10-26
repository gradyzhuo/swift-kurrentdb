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
        case let .event(readEvent): readEvent.record.eventType
        case .caughtUp: "caughtUp"
        case .fellBehind: "fellBehind"
        case .checkpoint: "checkpoint"
        }
    }

    @Test("A subscription from the start delivers the stored events, then caughtUp")
    func testCaughtUpFollowsTheStoredEvents() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        try await client.streams(specified: streamName).append(events: [
            EventData(eventType: "Messages-A", data: Data(), contentType: .json),
            EventData(eventType: "Messages-B", data: Data(), contentType: .json),
        ]) { $0.expectedRevision = .any }

        let subscription = try await client.streams(specified: streamName).subscribe { $0.revision = .start }
        var seen: [String] = []
        for try await message in subscription.messages {
            seen.append(Self.label(message))
            if case .caughtUp = message { break }
        }
        subscription.cancel()
        #expect(seen == ["Messages-A", "Messages-B", "caughtUp"])
    }

    @Test("A live event arrives after caughtUp")
    func testEventsKeepArrivingAfterCaughtUp() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }

        let subscription = try await client.streams(specified: streamName).subscribe()
        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "Messages-Live", data: Data(), contentType: .json)]) { $0.expectedRevision = .any }

        var seen: [String] = []
        for try await message in subscription.messages {
            seen.append(Self.label(message))
            if case .event = message { break }
        }
        subscription.cancel()
        #expect(seen.last == "Messages-Live")
        #expect(seen.dropLast().allSatisfy { $0 == "caughtUp" })
    }

    @Test("A filtered $all subscription reports a checkpoint while scanning events the filter rejects")
    func testFilteredAllSubscriptionReportsCheckpoints() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        // Enough events the filter rejects for at least one checkpoint interval (32 × 1) to pass.
        try await client.streams(specified: UUID().uuidString).append(
            events: (0 ..< 40).map { _ in EventData(eventType: "Messages-Noise", data: Data(), contentType: .json) }
        ) { $0.expectedRevision = .any }

        let subscription = try await client.allStreams.subscribe {
            $0.position = .start
            $0.filter = .onStreamName(prefixes: "no-such-stream-\(UUID().uuidString)").max(32).checkpointIntervalMultiplier(1)
        }
        // The first checkpoint is the start position itself; the next ones move forward.
        var checkpoints: [UInt64] = []
        for try await message in subscription.messages {
            if case let .checkpoint(position) = message { checkpoints.append(position.commit) }
            if case .caughtUp = message { break }
            if checkpoints.count == 3 { break }
        }
        subscription.cancel()
        #expect(checkpoints.count == 3, "checkpoints before caughtUp: \(checkpoints)")
        #expect(checkpoints == checkpoints.sorted() && checkpoints.last ?? 0 > 0)
    }

    /// KurrentDB 26.2.2 is the first server that sends `fellBehind` (to a client declaring
    /// compatibility 2); older ones switch back to catch-up silently. CI sets the flag on 26.2.
    @Test("A consumer that stalls while the stream is written to is told it fell behind, then that it caught up again",
          .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_SUPPORTS_FELL_BEHIND"] == "true"))
    func testFellBehindWhenTheConsumerStalls() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }

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
        while let message = try await iterator.next() {
            switch message {
            case .event: events += 1
            case .fellBehind: behind = true; notifications.append("fellBehind")
            case .caughtUp: behind = false; notifications.append("caughtUp")
            case .checkpoint: notifications.append("checkpoint")
            }
            // The last events may arrive live after the final caughtUp, so stop on the count.
            if events == batches * perBatch, !behind { break }
        }
        subscription.cancel()
        // Every return to catch-up is announced, and every catch-up ends with caughtUp.
        #expect(notifications.first == "fellBehind", "\(notifications)")
        #expect(notifications == Array(repeating: ["fellBehind", "caughtUp"], count: notifications.count / 2).flatMap { $0 }, "\(notifications)")
        #expect(events == batches * perBatch)   // the switch to catch-up neither drops nor repeats an event
    }

    @Test("Tombstoning the stream ends messages with resourceDeleted too")
    func testTombstoneEndsMessagesWithResourceDeleted() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
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
        defer { try? client.shutdown() }

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
