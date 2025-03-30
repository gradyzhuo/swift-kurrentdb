//
//  PresistentSubscriptionTests.swift
//
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
        settings = .localhost()
        groupName = "test-for-persistent-subscriptions"
    }

    @Test("Create PersistentSubscription for Stream")
    func testCreateToStream() async throws {
        let streamName = "test-persistent-subscription:\(UUID().uuidString)"
        let client = KurrentDBClient(settings: .localhost())
        let persistentSubscriptions = client.streams(of: streamName).persistentSubscriptions(group: groupName)
        try await persistentSubscriptions.create(options: .init())

        let subscriptions = try await client.persistentSubscriptions.list(for: .stream(.init(name: streamName)))
        #expect(subscriptions.count == 1)

        try await persistentSubscriptions.delete()
    }

    @Test("Subscribe PersistentSubscription for Stream")
    func testSubscribeToStream() async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: .localhost())
        let streams = client.streams(of: .specified(streamIdentifier))
        
        let persistentSubscriptions = streams.persistentSubscriptions(group: groupName)
        try await persistentSubscriptions.create()

        let subscription = try await persistentSubscriptions.subscribe()

        let response = try await streams.append(events: [
            .init(
                eventType: "PS-SubscribeToStream-AccountCreated", payload: ["Description": "Gears of War 10"]
            ),
        ], options: .init().revision(expected: .any))

        var lastEventResult: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            lastEventResult = result
            try await subscription.ack(readEvents: result.event)
            break
        }

        #expect(response.currentRevision == lastEventResult?.event.record.revision)

        try await streams.delete()
        try await persistentSubscriptions.delete()
    }

    @Test("Subscribe PersistentSubscription for Stream")
    func testSubscribeToAll() async throws {
        let client = KurrentDBClient(settings: .localhost())
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let streams = client.streams(of: .specified(streamIdentifier))
        
        let persistentSubscriptions = streams.persistentSubscriptions(group: groupName)
        
        try await persistentSubscriptions.create()

        let subscription = try await persistentSubscriptions.subscribe()

        let event = EventData(
            eventType: "PS-SubscribeToAll-AccountCreated", payload: ["Description": "Gears of War 10:\(UUID().uuidString)"]
        )

        
        let response = try await streams.append(events: [
            event,
        ], options: .init().revision(expected: .any))

        var lastEventResult: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            try await subscription.ack(readEvents: result.event)

            if result.event.record.eventType == event.eventType {
                lastEventResult = result
                break
            }
        }

        #expect(response.position?.commit == lastEventResult?.event.commitPosition?.commit)

        try await streams.delete()
        try await persistentSubscriptions.delete()
    }
}
