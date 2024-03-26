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
        try EventStoreDB.using(settings: "esdb://localhost:2113?tls=false")
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
//    func testDelete() async throws {
//        var client = try EventStoreDB.Client()
//        try await client.persistentSubscriptionsClient.deleteOn(stream: .specified("testing"), groupName: "mytest")
//        
//    }

    func testCreate() async throws {
        var client = try EventStoreDB.Client()
        try await client.persistentSubscriptionsClient.createToStream(streamName: "testing", groupName: "mytest", options: .init())
        
    }
    
    func testSubscribe() async throws {
        let client = try EventStoreDB.Client()
        
//        try await client.persistentSubscriptionsClient.replayParkedMessages(stream: .specified("testing"), groupName: "mytest") { options in
//            options.stop(at: .noLimit)
//        }
        
        let subscription = try await client.persistentSubscriptionsClient.subscribeTo(.specified("testing"), groupName: "mytest", options: .init())
        
//        for try await event in subscription {
//            print("sub: \(event)")
//            try await subscription.ack(eventIds: event.event.id)
//        }
        
    }
}
