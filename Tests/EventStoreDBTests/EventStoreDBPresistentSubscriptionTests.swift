//
//  EventStoreDBPresistentSubscriptionTests.swift
//
//
//  Created by Grady Zhuo on 2024/3/25.
//

@testable import EventStoreDB
import SwiftProtobuf
import XCTest
import GRPC

final class EventStoreDBPersistentSubscriptionTests: XCTestCase {
    let streamName = "testing"
    let groupName = "mytest"

    func testCreate() async throws {
        let settings = ClientSettings.localhost()
        let subscriptionClient = try PersistentSubscriptionsClient(channel: GRPCChannelPool.with(settings: settings), callOptions: settings.makeCallOptions())
        let streamSelector: EventStoreDB.Selector<EventStoreDB.Stream.Identifier> = .specified(streamName: streamName)
        try await subscriptionClient.deleteOn(stream: streamSelector, groupName: groupName)
        
        
        let client = EventStoreDBClient(settings: settings)
        try await client.createPersistentSubscription(to: "testing", groupName: "mytest")
        
        let subscriptions = try await subscriptionClient.list(stream: streamSelector)
        XCTAssertEqual(subscriptions.count, 1)
    }

    func testSubscribe() async throws {
        let settings = ClientSettings.localhost()
        let client = EventStoreDBClient(settings: settings)

        let subscription = try await client.subscribePersistentSubscription(to: .specified("testing"), groupName: "mytest") { options in
            options
        }

        let response = try await client.appendStream(to: "testing",
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

        XCTAssertEqual(response.current.revision, lastEventResult?.event.recordedEvent.revision)
    }
}
