//
//  EventStoreDBPresistentSubscriptionTests.swift
//
//
//  Created by Grady Zhuo on 2024/3/25.
//

@testable import EventStoreDB
import GRPC
import SwiftProtobuf
import XCTest
import NIOPosix
import Testing


@Suite("EventStoreDB Persistent Subscription Tests")
final class EventStoreDBPersistentSubscriptionTests: Sendable {
    
    let client: EventStoreDBClient
    let groupName: String
    let streamSelector: EventStoreDB.Selector<EventStoreDB.Stream.Identifier>
    let streamIdentifier: EventStoreDB.Stream.Identifier
    
    init() async throws {
        self.client = .init(settings: ClientSettings.localhost())
        self.streamIdentifier = Stream.Identifier.init(name: UUID().uuidString)
        self.groupName = streamIdentifier.name
        self.streamSelector = .specified(streamIdentifier)
    }
    
    deinit {
        let client = client
        let streamSelector = streamSelector
        let groupName = groupName
        Task.detached {
            try await client.deletePersistentSubscription(streamSelector: streamSelector, groupName: groupName)
        }
    }
    
    @Test("Create PersistentSubscription for Stream")
    func testCreateToStream() async throws{
        
        try await client.createPersistentSubscription(to: streamIdentifier, groupName: groupName)
        let subscriptions = try await client.listPersistentSubscription(streamSelector: .specified(streamIdentifier))
        
        #expect(subscriptions.count == 1)
    }
    
    @Test("Subscribe PersistentSubscription for Stream")
    func testSubscribeToStream() async throws {
        try await testCreateToStream()

        let subscription = try await client.subscribePersistentSubscription(to: streamSelector, groupName: groupName) { options in
            options
        }

        let response = try await client.appendStream(to: streamIdentifier,
                                                     events: .init(
                                                         eventType: "AccountCreated", payload: ["Description": "Gears of War 10"]
                                                     )) { options in
            options.revision(expected: .any)
        }
        
        var lastEventResult: PersistentSubscriptionsClient.Subscription.EventResult? = nil
        for try await result in subscription {
            lastEventResult = result
            try await subscription.ack(readEvents: result.event)
            break
        }
        
        #expect(response.current.revision == lastEventResult?.event.recordedEvent.revision)
    }
}
