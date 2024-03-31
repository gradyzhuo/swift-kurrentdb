//
//  EventStoreDBStreamTests.swift
//
//
//  Created by Grady Zhuo on 2023/10/28.
//


@testable import struct EventStoreDB.Stream
@testable import EventStoreDB
import GRPC
import NIO
import XCTest

enum TestingError: Error {
    case exception(String)
}

final class EventStoreDBStreamTests: XCTestCase {
    var streamName: String!

    override func setUpWithError() throws {
//        var settings: ClientSettings = "esdb://admin:changeit@localhost:2111,localhost:2112,localhost:2113?keepAliveTimeout=10000&keepAliveInterval=10000"
//        settings.configuration.trustRoots = .crtInBundle("ca", inBundle: .module)
//        EventStoreDB.using(settings: .localhost())

//        try EventStoreDB.using(settings: "esdb://admin:changeit@localhost:2113")

//        try EventStoreDB.using(settings: .localhost(port: 2111, userCredentials: .init(username: "admin", password: "changeit"), trustRoots: .crtInBundle("ca", inBundle: .module)))
        try EventStoreDB.using(settings: .parse(connectionString: "esdb://localhost:2113?tls=false"))

        streamName = "testing2"
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testAppendEvent() async throws {
        let content = ["Description": "Gears of War 4"]
        
        let client = try EventStoreDB.Client()
        
        let readResponses = try client.read(streamName: streamName, cursor: .end) { options in
            options.set(uuidOption: .string)
                .countBy(limit: 1)
        }
        
        let lastRevision = await readResponses.first {
            switch $0.content {
            case .event:
                return true
            default:
                return false
            }
        }.flatMap{
            switch $0.content{
            case .event(let readEvent):
                return readEvent.recordedEvent.revision
            default:
                return nil
            }
        }
        
        let appendResponse = try await client.appendTo(streamName: streamName, events: .init(eventType: "AccountCreated", payload: content)) { options in
            options.expectedRevision(.any)
        }
        
        XCTAssertEqual(lastRevision.map{ $0 + 1 }, appendResponse.current.revision)
    }
}
