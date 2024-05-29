//
//  EventStoreDBPresistentSubscriptionTests.swift
//
//
//  Created by 卓俊諺 on 2024/3/25.
//

@testable import EventStoreDB
import SwiftProtobuf
import XCTest

final class EventStoreDBPersistentSubscriptionTests: XCTestCase {
    func testCreate() async throws {
        let settings = ClientSettings.localhost()
        let client = try await EventStoreDBClient(settings: settings)
        try await client.createPersistentSubscription(to: "testing", groupName: "mytest", options: .init())
    }

    func testSubscribe() async throws {
        let settings = ClientSettings.localhost()
        let client = try await EventStoreDBClient(settings: settings)

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
