//
//  PresistentSubscriptionTests.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2024/3/25.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("EventStoreDB Persistent Subscription Tests", .serialized)
struct PersistentSubscriptionsTests {
    let groupName: String
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
        groupName = "test-for-persistent-subscriptions"
    }

    @Test("Create PersistentSubscription for Stream")
    func testCreateToStream() async throws {
        let streamName = "test-persistent-subscription:\(UUID().uuidString)"
        let streamIdentifier = StreamIdentifier(name: streamName)
        let client = KurrentDBClient(settings: settings)

        try await client.createPersistentSubscription(stream: streamIdentifier, groupName: groupName)

        let subscriptions = try await client.listPersistentSubscriptions(stream: streamIdentifier)
        #expect(subscriptions.count == 1)

        try await client.deletePersistentSubscription(stream: streamIdentifier, groupName: groupName)
    }

    @Test("Subscribe PersistentSubscription for Stream")
    func testSubscribeToStream() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: settings)

        try await client.createPersistentSubscription(stream: streamIdentifier, groupName: groupName)

        let subscription = try await client.subscribePersistentSubscription(stream: streamIdentifier, groupName: groupName)

        let response = try await client.appendStream(streamIdentifier, events: [
            .init(eventType: "PS-SubscribeToStream-AccountCreated", model: ["Description": "Gears of War 10"]),
        ]) {
            $0.revision(expected: .any)
        }

        var lastEventResult: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            lastEventResult = result
            try await subscription.ack(readEvents: result.event)
            break
        }

        #expect(response.currentRevision == lastEventResult?.event.record.revision)

        try await client.deleteStream(streamIdentifier)
        try await client.deletePersistentSubscription(stream: streamIdentifier, groupName: groupName)
    }

    @Test("Subscribe PersistentSubscription for All Streams")
    func testSubscribeToAll() async throws {
        let client = KurrentDBClient(settings: settings)
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

        try await client.createPersistentSubscription(stream: streamIdentifier, groupName: groupName)

        let subscription = try await client.subscribePersistentSubscription(stream: streamIdentifier, groupName: groupName)

        let event = EventData(
            eventType: "PS-SubscribeToAll-AccountCreated", model: ["Description": "Gears of War 10:\(UUID().uuidString)"]
        )

        let response = try await client.appendStream(streamIdentifier, events: [event]) {
            $0.revision(expected: .any)
        }

        var lastEventResult: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            try await subscription.ack(readEvents: result.event)

            if result.event.record.eventType == event.eventType {
                lastEventResult = result
                break
            }
        }

        #expect(response.position?.commit == lastEventResult?.event.commitPosition?.commit)

        try await client.deleteStream(streamIdentifier)
        try await client.deletePersistentSubscription(stream: streamIdentifier, groupName: groupName)
    }
}
