//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/25.
//

@testable import EventStoreDB
import SwiftProtobuf
import XCTest

final class EventStoreDBPersistentSubscriptionTests: XCTestCase {
    override func setUpWithError() throws {
        try EventStore.using(settings: "esdb://localhost:2113?tls=false")
    }

//    override func setUp() async throws {
//        let client = try EventStoreDB.Client()
//        
//    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
//        Task{
//            let client = try EventStoreDB.Client()
//            try await client.persistentSubscriptionsClient.deleteOn(stream: .specified("testing"), groupName: "mytest")
//        }
//        
    }

    func testCreate() async throws {
//        let client = try EventStoreDB.Client()
//        try await client.createPersistentSubscription(streamName: "testing", groupName: "mytest", options: .init())
        
    }
    
    func testSubscribe() async throws {
        let client = try EventStoreDB.Client()
        
        let subscription = try await client.subscribePersistentSubscriptionTo(.specified("testing"), groupName: "mytest") { options in
            options
        }

        let response = try await client.appendTo(streamName: "testing", events: .init(eventType: "AccountCreated", payload: ["Description": "Gears of War 10"])) { options in
            options.expectedRevision(.any)
        }
        
        var firstEventResult: PersistentSubscriptionsClient.Read.EventResult? = nil
        for try await result in subscription {
            firstEventResult = result
            try await subscription.ack(readEvents: result.event)
            break
        }
        
        XCTAssertEqual(response.current.revision, firstEventResult?.event.recordedEvent.revision)
        
    }
}
