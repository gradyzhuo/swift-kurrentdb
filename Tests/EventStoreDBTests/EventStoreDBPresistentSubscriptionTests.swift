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

final class EventStoreDBPersistentSubscriptionTests: XCTestCase {
    let streamName = UUID().uuidString
    let groupName = UUID().uuidString
    let settings = ClientSettings.localhost()
    lazy var streamSelector: EventStoreDB.Selector<EventStoreDB.Stream.Identifier> = .specified(streamName: streamName)

    lazy var subscriptionClient: PersistentSubscriptionsClient = try! PersistentSubscriptionsClient(channel: GRPCChannelPool.with(settings: settings), callOptions: settings.makeCallOptions())

    override func setUp() async throws {
        let subscriptionClient = try PersistentSubscriptionsClient(channel: GRPCChannelPool.with(settings: settings), callOptions: settings.makeCallOptions())
        do {
            try await subscriptionClient.deleteOn(stream: streamSelector, groupName: groupName)
        } catch {
            print("subscription does not exists.")
        }
    }

    func testCreate() async throws {
        let client = EventStoreDBClient(settings: settings)
        try await client.createPersistentSubscription(to: .init(name: streamName), groupName: groupName)

        let subscriptions = try await subscriptionClient.list(stream: streamSelector)
        XCTAssertEqual(subscriptions.count, 1)
    }

    func testSubscribe() async throws {
        try await testCreate()

        let settings = ClientSettings.localhost()
        let client = EventStoreDBClient(settings: settings)

        let subscription = try await client.subscribePersistentSubscription(to: streamSelector, groupName: groupName) { options in
            options
        }

        let response = try await client.appendStream(to: .init(name: streamName),
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
