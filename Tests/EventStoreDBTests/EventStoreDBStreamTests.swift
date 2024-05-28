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
import Testing
import XCTest

enum TestingError: Error {
    case exception(String)
}

final class EventStoreDBStreamTests: XCTestCase {
    var streamName: String!

    func testAll() async {
        await XCTestScaffold.runAllTests(hostedBy: self)
    }

    override func setUp() async throws {
        try await EventStoreDB.using(settings: .parse(connectionString: "esdb://localhost:2113?tls=false"))

        streamName = "testing2"
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testStreamNoFound() async throws {
        let client = try await EventStoreDBClient()
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
        let content = ["Description": "Gears of War 4"]

        let client = try await EventStoreDBClient()

        let readResponses = try client.readStream(to: .init(name: streamName), cursor: .end) { options in
            options.set(uuidOption: .string)
                .set(limit: 1)
        }

        let lastRevision = try await readResponses.first {
            switch $0.content {
            case .event:
                true
            default:
                false
            }
        }.flatMap {
            switch $0.content {
            case let .event(readEvent):
                readEvent.recordedEvent.revision
            default:
                nil
            }
        }

        let appendResponse = try await client.appendStream(to: .init(name: streamName), events: .init(eventType: "AccountCreated", payload: content)) { options in
            options.revision(expected: .any)
        }

        XCTAssertEqual(lastRevision.map { $0 + 1 }, appendResponse.current.revision)
    }
}
