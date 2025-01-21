//
//  EventStoreDBPresistentSubscriptionTests.swift
//
//
//  Created by Grady Zhuo on 2024/3/25.
//

@testable import PersistentSubscriptions
import KurrentCore
import Foundation
import Testing
import Streams

@Suite("EventStoreDB Persistent Subscription Tests")
final class EventStoreDBPersistentSubscriptionsTests {
    
    let groupName: String
    let streamIdentifier: KurrentCore.Stream.Identifier
    let settings: ClientSettings
    
    init() async throws {
        self.settings = .localhost()
        self.streamIdentifier = Stream.Identifier.init(name: UUID().uuidString)
        self.groupName = streamIdentifier.name
//        self.streamSelector = .specified(streamIdentifier)
    }
    
    deinit {
//        let client = client
//        let streamSelector = streamSelector
//        let groupName = groupName
//        Task {
//            try await client.deletePersistentSubscription(streamSelector: streamSelector, groupName: groupName)
//        }
    }
    
    @Test("Create PersistentSubscription for Stream")
    func testCreateToStream() async throws{
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings)
        try await persistentSubscriptions.createToStream(streamIdentifier: streamIdentifier, groupName: groupName, options: .init())
        
        let subscriptions = try await persistentSubscriptions.list(streamSelector: .specified(streamIdentifier))
        #expect(subscriptions.count == 1)
        
        try await persistentSubscriptions.delete(stream: .specified(streamIdentifier), groupName: groupName)
    }
    
    @Test("Subscribe PersistentSubscription for Stream")
    func testSubscribeToStream() async throws {
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings)
        try await persistentSubscriptions.createToStream(streamIdentifier: streamIdentifier, groupName: groupName, options: .init())
        
        let subscription = try await persistentSubscriptions.subscribe(.specified(streamIdentifier), groupName: groupName, options: .init())
        
        
        let streams = Streams.Service(settings: settings)
        let response = try await streams.append(to: streamIdentifier, events: [
            .init(
                eventType: "AccountCreated", payload: ["Description": "Gears of War 10"]
            )
        ], options: .init().revision(expected: .any))
        
        var lastEventResult: PersistentSubscription.EventResult? = nil
        for try await result in subscription.events {
            lastEventResult = result
            try await subscription.ack(readEvents: result.event)
            break
        }
        
        #expect(response.current.revision == lastEventResult?.event.recordedEvent.revision)
        
        try await persistentSubscriptions.delete(stream: .specified(streamIdentifier), groupName: groupName)
    }
}
