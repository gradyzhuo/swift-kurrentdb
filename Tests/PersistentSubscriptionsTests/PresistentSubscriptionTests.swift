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
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        groupName = "test-for-persistent-subscriptions"
    }

    @Test("Create PersistentSubscription for Stream")
    func testCreateToStream() async throws {
        let streamName = "test-persistent-subscription:\(UUID().uuidString)"
        let client = KurrentDBClient(settings: settings)

        try await client.persistentSubscriptions(of: .specified(stream: streamName, group: groupName)).create()

        let subscriptions = try await client.persistentSubscriptions(filterStream: streamName).list()
        #expect(subscriptions.count == 1)

        try await client.persistentSubscriptions(stream: streamName, group: groupName).delete()
    }

    @Test("Subscribe PersistentSubscription for Stream")
    func testSubscribeToStream() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        let persistentSubscription = client.persistentSubscriptions(stream: streamName, group: groupName)
        try await persistentSubscription.create()

        let subscription = try await persistentSubscription.subscribe()

        let response = try await client.streams(specified: streamName).append(events: [
            .init(eventType: "PS-SubscribeToStream-AccountCreated", model: ["Description": "Gears of War 10"])
        ]) { $0.expectedRevision = .any }

        var lastEventResult: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            lastEventResult = result
            try await subscription.ack(readEvents: result.event)
            break
        }

        #expect(response.currentRevision == lastEventResult?.event.record.revision)

        try await client.streams(specified: streamName).delete()
        try await persistentSubscription.delete()
    }

    @Test("Subscribe PersistentSubscription for All Streams")
    func testSubscribeToAll() async throws {
        let client = KurrentDBClient(settings: settings)
        let streamName = UUID().uuidString

        let persistentSubscription = client.persistentSubscriptions(of: .allStreams(group: groupName))
        try await persistentSubscription.create()

        let subscription = try await persistentSubscription.subscribe()

        let event = EventData(
            eventType: "PS-SubscribeToAll-AccountCreated", model: ["Description": "Gears of War 10:\(UUID().uuidString)"]
        )

        let response = try await client.streams(specified: streamName)
            .append(events: [event]) { $0.expectedRevision = .any }

        var lastEventResult: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            try await subscription.ack(readEvents: result.event)

            if result.event.record.eventType == event.eventType {
                lastEventResult = result
                break
            }
        }

        #expect(response.position?.commit == lastEventResult?.event.commitPosition?.commit)

        try await client.streams(specified: streamName).delete()
        try await persistentSubscription.delete()
    }
}
