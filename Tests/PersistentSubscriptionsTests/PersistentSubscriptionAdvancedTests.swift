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

@Suite("Persistent Subscription Advanced Tests", .serialized)
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
                events: [EventData(eventType: "PS-Nack-Event", model: ["x": 1])],
                options: .init().revision(expected: .any)
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
            .append(
                events: [EventData(eventType: "PS-NackRetry-Event", model: ["x": 2])],
                options: .init().revision(expected: .any)
            )

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

        var updateOptions = PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options()
        updateOptions.settings.maxRetryCount = 5
        try await ps.update(options: updateOptions)

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

        try await ps.create()
        let subscription = try await ps.subscribe()

        try await client.streams(specified: streamName)
            .append(
                events: [EventData(eventType: "PS-ReplayParked", model: ["x": 3])],
                options: .init().revision(expected: .any)
            )

        // Park the event
        for try await result in subscription.events {
            try await subscription.nack(readEvents: result.event, action: .park, reason: "park-for-replay-test")
            break
        }

        // Trigger replay — parked messages are re-queued for delivery
        try await ps.replayParked()

        // Verify the event is re-delivered and ACK it
        var redelivered = false
        for try await result in subscription.events {
            try await subscription.ack(readEvents: result.event)
            redelivered = true
            break
        }

        #expect(redelivered)
        try await ps.delete()
        try await client.streams(specified: streamName).delete()
    }
}
