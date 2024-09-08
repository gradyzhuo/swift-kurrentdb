//
//  EventStoreDBStreamTests.swift
//
//
//  Created by Grady Zhuo on 2023/10/28.
//

@testable import EventStoreDB
// @testable import struct EventStoreDB.Stream
import GRPC
import NIO
import XCTest

enum TestingError: Error {
    case exception(String)
}

final class EventStoreDBStreamTests: XCTestCase {
    var streamName: String!

    override func setUp() async throws {
        streamName = "testing2"
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStreamNoFound() async throws {
        let settings = ClientSettings.localhost()
        let client = EventStoreDBClient(settings: settings)
        var anError: Error?
        do {
            for try await _ in try client.readStream(to: "NoStream", cursor: .start) {
                // no thing
            }
        } catch {
            anError = error
        }

        XCTAssertNotNil(anError)
    }

    func testAppendEvent() async throws {
        let streamIdentifier = Stream.Identifier(name: UUID().uuidString)
        let content = ["Description": "Gears of War 4"]
        let settings = ClientSettings.localhost()
        let client = EventStoreDBClient(settings: settings)

        let appendResponse = try await client.appendStream(to: streamIdentifier, events: .init(eventType: "AccountCreated", payload: content)) { options in
            options.revision(expected: .any)
        }
        
        let responses = try client.readStream(to: streamIdentifier, cursor: .start)
        for try await response in responses{
            print("xxxx:", response)
        }
        
        try await client.deleteStream(to: streamIdentifier) { options in
            options.revision(expected: .streamExists)
        }

        XCTAssertEqual(appendResponse.current.revision, 0)
    }

    func testMetadata() async throws {
        let settings = ClientSettings.localhost()
        let client = EventStoreDBClient(settings: settings)

        let metadata = Stream.Metadata()
            .cacheControl(.seconds(3))
            .maxAge(.seconds(30))
            .acl(.userStream)

        try await client.setMetadata(to: .init(name: streamName), metadata: metadata) { options in
            options
        }

        guard let responseMetadata = try await client.getStreamMetadata(to: .init(name: streamName)) else {
            throw TestingError.exception("metadata not found.")
        }

        XCTAssertEqual(metadata, responseMetadata)
    }

    func testSubscribe() async throws {
        let settings = ClientSettings.localhost()
        let client = EventStoreDBClient(settings: settings)

        let subscription = try await client.subscribeTo(stream: .init(name: streamName), from: .end)

        let response = try await client.appendStream(to: .init(name: streamName),
                                                     events: .init(
                                                         eventType: "AccountCreated", payload: ["Description": "Gears of War 10"]
                                                     )) { options in
            options.revision(expected: .any)
        }

        var lastEventResult: StreamClient.Subscription.EventAppeared? = nil
        for try await result in subscription {
            lastEventResult = result
            break
        }

        XCTAssertEqual(response.current.revision, lastEventResult?.event.recordedEvent.revision)
    }
}
