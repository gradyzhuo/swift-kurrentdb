//
//  EventStoreDBStreamTests.swift
//
//
//  Created by Grady Zhuo on 2023/10/28.
//

import Foundation
@testable import KurrentStreams
import EventStoreDB
import Testing


@Suite("EventStoreDB Stream Tests", .serialized)
final class StreamTests: Sendable{
    
    let streamIdentifier: StreamIdentifier
    let settings: ClientSettings
    
    init () async throws {
        self.streamIdentifier = .init(name: UUID().uuidString)
        self.settings = .localhost()
    }
    
    @Test("Stream should be not found and throw an error.")
    func testStreamNoFound() async throws {
        let streams = Streams(settings: .localhost())
        
        await #expect(throws: EventStoreError.self){
            let responses = try await streams.read(streamIdentifier, cursor: .start, options: .init())
            var responsesIterator = responses.makeAsyncIterator()
            let test = try await responsesIterator.next()
            print(test)
        }
        
    }
    
    @Test("It should be succeed when append event to stream.", arguments: [
        [
            EventData(eventType: "AccountCreated", payload: ["Description": "Gears of War 4"]),
            EventData(eventType: "AccountDeleted", payload: ["Description": "Gears of War 4"])
        ]
    ])
    func testAppendEvent(events: [EventData]) async throws {
        let streams = Streams(settings: .localhost())
        let appendResponse = try await streams.append(to: streamIdentifier, events: events, options: .init().revision(expected: .any))

        let appendedRevision = try #require(appendResponse.currentRevision)
        let readResponses = try await streams.read(streamIdentifier, cursor: .specified(.forwardOn(revision: appendedRevision)), options: .init())
        let firstResponse = try await readResponses.first{ _ in true}
        guard case .event(let readEvent) = firstResponse?.content,
              let readPosition = readEvent.commitPosition,
              let position = appendResponse.position else{
            throw TestingError.exception("readResponse.content or appendResponse.position is not Event or Position")
        }
        
        #expect(readPosition == position)
        
        try await streams.delete(streamIdentifier)
    }
    
    @Test("It should be succeed when set metadata to stream.")
    func testMetadata() async throws {
        let metadata = StreamMetadata()
            .cacheControl(.seconds(3))
            .maxAge(.seconds(30))
            .acl(.userStream)

        let streams = Streams(settings: settings)
        try await streams.setMetadata(to: streamIdentifier, metadata: metadata, options: .init())
        
        let responseMetadata = try #require(try await streams.getMetadata(on: streamIdentifier))
        #expect(metadata == responseMetadata)
        try await streams.delete(streamIdentifier)
    }
    
    @Test("It should be succeed when subscribe to stream.")
    func testSubscribe() async throws {
        let streams = Streams(settings: .localhost())
        
        let subscription = try await streams.subscribe(self.streamIdentifier, cursor: .end, options: .init())
        let response = try await streams.append(to: self.streamIdentifier,
                                                      events: [
                                                         .init(
                                                            eventType: "AccountCreated", payload: ["Description": "Gears of War 10"]
                                                         )
                                                      ], options: .init().revision(expected: .any))
        
        var lastEventResult: ReadEvent?
        for try await event in subscription.events {
            lastEventResult = event
            break
        }

        let lastEventRevision = try #require(lastEventResult?.recordedEvent.revision)
        #expect(response.currentRevision == lastEventRevision)
        try await streams.delete(streamIdentifier)
   }
    
    @Test("It should be succeed when subscribe to all streams.")
    func testSubscribeAll() async throws {
        let streams = Streams(settings: .localhost())
        
        let subscription = try await streams.subscribeToAll(cursor: .end, options: .init())
        let response = try await streams.append(to: self.streamIdentifier,
                                                      events: [
                                                         .init(
                                                            eventType: "AccountCreated", payload: ["Description": "Gears of War 10"]
                                                         )
                                                      ], options: .init().revision(expected: .any))
        
        var lastEventResult: ReadEvent?
        for try await event in subscription.events {
            lastEventResult = event
            break
        }

        let lastEventPosition = try #require(lastEventResult?.recordedEvent.position)
        #expect(response.position?.commit == lastEventPosition.commit)
        try await streams.delete(streamIdentifier)
   }
        
        
    @Test("Testing streamAcl encoding and decoding should be succeed.", arguments: [
        (StreamMetadata.Acl.systemStream, "$systemStreamAcl"),
        (StreamMetadata.Acl.userStream, "$userStreamAcl")
    ])
    func testSystemStreamAclEncodeAndDecode(acl: StreamMetadata.Acl, value: String) throws {
        let encoder = JSONEncoder()
        let encodedData = try #require(try encoder.encode(value))
        
        #expect(try acl.rawValue == encodedData)

        let decoder = JSONDecoder()
        #expect(try decoder.decode(StreamMetadata.Acl.self, from: encodedData) == acl)
    }


    
}

