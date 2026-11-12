//
//  PersistentSubscriptionAdvancedTests.swift
//  swift-kurrentdb
//
//  Integration tests for persistent subscription NACK, getInfo, update,
//  and list operations. Requires a running KurrentDB instance.
//

import Foundation
@testable import KurrentDB
import Testing

// `.timeLimit` is the last backstop: a test (above all the redelivery loop over
// `subscription2.events` in testReplayParked) that waits without end for an unexpected reason fails at this limit, instead of hanging CI until it is killed.
// It is an operational limit, not a timing assertion; a healthy test stays far below it.
@Suite("Persistent Subscription Advanced Tests", .serialized, .timeLimit(.minutes(2)))
struct PersistentSubscriptionAdvancedTests: Sendable {
    let settings: ClientSettings
    let groupName: String

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        groupName = "test-ps-advanced-\(UUID().uuidString)"
    }

    // MARK: - NACK

    @Test("NACK with park action sends event to parked queue without error")
    func testNackWithPark() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()
        let subscription = try await ps.subscribe()

        try await client.streams(specified: streamName)
            .append(
                events: [EventData(eventType: "PS-Nack-Event", model: ["x": 1])]
            )

        var received: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            received = result
            try await subscription.nack(readEvents: result.event, action: .park, reason: "unit-test-park")
            break
        }

        #expect(received != nil)
        try await ps.delete()
        try await client.streams(specified: streamName).delete()
    }

    @Test("NACK with retry action re-delivers the event")
    func testNackWithRetry() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()
        let subscription = try await ps.subscribe()

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "PS-NackRetry-Event", model: ["x": 2])]) {
                $0.expectedRevision = .any
            }

        // Receive once and NACK with retry, then ACK on retry delivery
        var deliveries = 0
        for try await result in subscription.events {
            deliveries += 1
            if deliveries == 1 {
                try await subscription.nack(readEvents: result.event, action: .retry, reason: "unit-test-retry")
            } else {
                try await subscription.ack(readEvents: result.event)
                break
            }
        }

        #expect(deliveries == 2)
        try await ps.delete()
        try await client.streams(specified: streamName).delete()
    }

    // MARK: - getInfo

    @Test("getInfo returns correct group name and event source")
    func testGetInfo() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()

        let info = try await ps.getInfo()
        #expect(info.groupName == groupName)
        #expect(info.eventSource == streamName)

        try await ps.delete()
    }

    @Test("getInfo for $all subscription returns '$all' event source")
    func testGetInfoAllStream() async throws {
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(of: .allStreams(group: groupName))

        try await ps.create()

        let info = try await ps.getInfo()
        #expect(info.groupName == groupName)
        #expect(info.eventSource == "$all")

        try await ps.delete()
    }

    // MARK: - Update

    @Test("Update subscription settings does not throw")
    func testUpdateSubscription() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)        
        try await ps.create()
        
        try await ps.update { $0.settings.maxRetryCount = 5 }

        // getInfo to confirm the setting was applied
        let info = try await ps.getInfo()
        #expect(info.maxRetryCount == 5)

        try await ps.delete()
    }

    // MARK: - List

    @Test("List subscriptions for a stream returns created subscription")
    func testListSubscriptionsForStream() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()

        let subscriptions = try await client.persistentSubscriptions(filterStream: streamName).list()
        #expect(subscriptions.contains { $0.groupName == groupName })

        try await ps.delete()
    }

    @Test("Delete subscription removes it from the list")
    func testDeleteSubscriptionRemovesFromList() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()
        try await ps.delete()

        let subscriptions = try await client.persistentSubscriptions(filterStream: streamName).list()
        #expect(!subscriptions.contains { $0.groupName == groupName })
    }

    // MARK: - Replay parked

    @Test("Replay parked messages re-delivers parked events")
    func testReplayParked() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create{
            $0.revision = .start
            $0.settings.messageTimeout = .ms(6000)
        }
        let subscription = try await ps.subscribe()

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "PS-ReplayParked", model: ["x": 3])]) {
                $0.expectedRevision = .any
            }

        // Park the event
        for try await result in subscription.events {
            try await subscription.nack(readEvents: result.event, action: .park, reason: "park-for-replay-test")
            break
        }

        // nack(park) is fire-and-forget: it returns once enqueued, before the server has committed the park.
        // Wait until parkedMessageCount shows the park is done before starting the replay; otherwise the replay
        // may run before the park is committed, with nothing to replay, and the second subscription below never sees the redelivery.
        // Poll the real precondition, not a fixed sleep; the limit is a fast-fail backstop, not a timing assumption.
        // It must be `#require` (throws and stops), not `#expect` (records and goes on):
        // otherwise, with no park observed, the test would go on to replay and wait without end on subscription2.events below.
        var parkedReady = false
        for _ in 0 ..< 50 {
            if try await ps.getInfo().parkedMessageCount >= 1 { parkedReady = true; break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try #require(parkedReady, "The park was not committed in the expected time; there is nothing to replay")

        // Trigger replay — parked messages are re-queued for delivery
        try await ps.replayParked()

        let subscription2 = try await ps.subscribe()
        // Verify the event is re-delivered and ACK it
        var redelivered = false
        for try await result in subscription2.events {
            try await subscription2.ack(readEvents: result.event)
            redelivered = true
            break
        }

        #expect(redelivered)
        try await ps.delete()
        try await client.streams(specified: streamName).delete()
    }
}
