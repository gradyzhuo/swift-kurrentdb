//
//  EventStoreDBStreamTests.swift
//
//
//  Created by Grady Zhuo on 2023/10/28.
//

import Foundation
@testable import Streams
import GRPCCore
import GRPCEncapsulates
import KurrentCore
import Testing


enum TestingError: Error {
    case exception(String)
}

@Suite("EventStoreDB Stream Tests", .serialized)
final class EventStoreDBStreamTests: Sendable{
    
    let streamIdentifier: KurrentCore.Stream.Identifier
    let settings: ClientSettings
    
    init () async throws {
        self.streamIdentifier = .init(name: UUID().uuidString)
        self.settings = .localhost()
//        self.client = .init(wrapping: <#T##GRPCClient#>, metadata: <#T##Metadata#>, callOptions: <#T##CallOptions#>)//.init(settings: ClientSettings.localhost())
    }
    
//    deinit {
//        let client = client
//        let streamIdentifier = streamIdentifier
//        Task.detached {
//            try await client.deleteStream(to: streamIdentifier) { options in
//                options.revision(expected: .streamExists)
//            }
//        }
//    }
    
    @Test("Stream should be not found and throw an error.")
    func testStreamNoFound() async throws {
        let streams = Streams.Service(settings: .localhost())
        
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
        let streams = Streams.Service(settings: .localhost())
        let appendResponse = try await streams.append(to: streamIdentifier, events: events, options: .init().revision(expected: .any))

        let appendedRevision = try #require(appendResponse.current.revision)
        let readResponses = try await streams.read(streamIdentifier, cursor: .specified(.forwardOn(revision: appendedRevision)), options: .init())
        let firstResponse = try await readResponses.first{ _ in true}
        guard case .event(let readEvent) = firstResponse?.content,
              let readPosition = readEvent.commitPosition,
              case .position(let position) = appendResponse.position else{
            throw TestingError.exception("readResponse.content or appendResponse.position is not Event or Position")
        }
        
        #expect(readPosition == position)
    }
//    
//    @Test("It should be succeed when set metadata to stream.")
//    func testMetadata() async throws {
//        let metadata = Stream.Metadata()
//            .cacheControl(.seconds(3))
//            .maxAge(.seconds(30))
//            .acl(.userStream)
//        
//        try await client.setMetadata(to: streamIdentifier, metadata: metadata) { options in
//            options
//        }
//        
//        let responseMetadata = try #require(try await client.getStreamMetadata(to: streamIdentifier))
//        #expect(metadata == responseMetadata)
//    }
//    
    @Test("It should be succeed when subscribe to stream.")
    func testSubscribe() async throws {
        let streams = Streams.Service(settings: .localhost())
        
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
        #expect(response.current.revision == lastEventRevision)
   }
    
    @Test("It should be succeed when subscribe to all streams.")
    func testSubscribeAll() async throws {
        let streams = Streams.Service(settings: .localhost())
        
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
        #expect(response.position.value?.commit == lastEventPosition.commit)
   }
        
        
    @Test("Testing streamAcl encoding and decoding should be succeed.", arguments: [
        (Stream.Metadata.Acl.systemStream, "$systemStreamAcl"),
        (Stream.Metadata.Acl.userStream, "$userStreamAcl")
    ])
    func testSystemStreamAclEncodeAndDecode(acl: KurrentCore.Stream.Metadata.Acl, value: String) throws {
        let encoder = JSONEncoder()
        let encodedData = try #require(try encoder.encode(value))
        
        #expect(try acl.rawValue == encodedData)

        let decoder = JSONDecoder()
        #expect(try decoder.decode(Stream.Metadata.Acl, from: encodedData) == acl)
    }


    
}

