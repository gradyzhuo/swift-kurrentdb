//
//  EventStoreDBStreamTests.swift
//
//
//  Created by Grady Zhuo on 2023/10/28.
//

import Foundation
@testable import EventStoreDB
import Testing


enum TestingError: Error {
    case exception(String)
}

@Suite("EventStoreDB Stream Tests")
final class EventStoreDBStreamTests: Sendable{
    
    let streamIdentifier: EventStoreDB.Stream.Identifier
    let client: EventStoreDBClient
    
    init () async throws {
        self.streamIdentifier = .init(name: UUID().uuidString)
        self.client = .init(settings: ClientSettings.localhost())
    }
    
    deinit {
        let client = client
        let streamIdentifier = streamIdentifier
        Task.detached {
            try await client.deleteStream(to: streamIdentifier) { options in
                options.revision(expected: .streamExists)
            }
        }
    }
    
    @Test("Stream should be not found and throw an error.")
    func testStreamNoFound() async throws {
        await #expect(throws: EventStoreError.self){
            var responsesIterator = try client.readStream(to: streamIdentifier, cursor: .start).makeAsyncIterator()
            _ = try await responsesIterator.next()
        }
    }
    
    @Test("It should be succeed when append event to stream.", arguments: [
        [
            EventData(eventType: "AccountCreated", payload: ["Description": "Gears of War 4"]),
            EventData(eventType: "AccountDeleted", payload: ["Description": "Gears of War 4"])
        ]
    ])
    func testAppendEvent(events: [EventData]) async throws {
        let appendResponse = try await client.appendStream(to: streamIdentifier, events: events) { options in
            options.revision(expected: .any)
        }
        
        var responsesIterator = try client.readStream(to: streamIdentifier, cursor: .end).makeAsyncIterator()
        let readResponse = try await responsesIterator.next()
        
        guard case .event(let readEvent) = readResponse?.content,
              let readPosition = readEvent.commitPosition,
              case .position(let position) = appendResponse.position else{
            throw TestingError.exception("readResponse.content or appendResponse.position is not Event or Position")
        }
        
        #expect(readPosition == position)
        
    }
    
    @Test("It should be succeed when set metadata to stream.")
    func testMetadata() async throws {
        let metadata = Stream.Metadata()
            .cacheControl(.seconds(3))
            .maxAge(.seconds(30))
            .acl(.userStream)
        
        try await client.setMetadata(to: streamIdentifier, metadata: metadata) { options in
            options
        }
        
        let responseMetadata = try #require(try await client.getStreamMetadata(to: streamIdentifier))
        #expect(metadata == responseMetadata)
    }
    
    @Test("It should be succeed when subscribe to stream.")
    func testSubscribe() async throws {
        let subscription = try await client.subscribeTo(stream: streamIdentifier, from: .end)
        
        let response = try await client.appendStream(to: streamIdentifier,
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
        
        let lastEventRevision = try #require(lastEventResult?.event.recordedEvent.revision)
        
        #expect(response.current.revision == lastEventRevision)
    }
    
    @Test("Testing streamAcl encoding and decoding should be succeed.", arguments: [
        (Stream.Metadata.Acl.systemStream, "$systemStreamAcl"),
        (Stream.Metadata.Acl.userStream, "$userStreamAcl")
    ])
    func testSystemStreamAclEncodeAndDecode(acl: EventStoreDB.Stream.Metadata.Acl, value: String) throws {
        let encoder = JSONEncoder()
        let encodedData = try #require(try encoder.encode(value))
        #expect(try acl.rawValue == encodedData)

        let decoder = JSONDecoder()
        #expect(try decoder.decode(Stream.Metadata.Acl, from: encodedData) == acl)
    }


    
}

