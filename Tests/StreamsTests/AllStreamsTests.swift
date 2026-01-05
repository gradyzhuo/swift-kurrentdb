//
//  StreamsTests.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2023/10/28.
//

import Foundation
@testable import KurrentDB
import Testing
import Logging

@Suite(.serialized)
struct `All Stream Tests`: Sendable {
    let settings: ClientSettings

    init() {
        settings = .localhost()
            .authenticated(.credentials(username: "admin", password: "changeit"))
    }

    @Test(arguments: [
        [
            EventData(eventType: "AppendEvent-AccountCreated", model: ["Description": "Gears of War 4"]),
            EventData(eventType: "AppendEvent-AccountDeleted", model: ["Description": "Gears of War 4"]),
        ],
    ])
    func `"It should succeed when read events from all streams without configuation."`(events: [EventData]) async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: settings)
        
        let appendResponse = try await client.appendStream(streamIdentifier, events: events) {
            $0.revision(expected: .any)
        }
        
        let responses = try await client.readAllStreams()
        
        let allEvents = try await responses.reduce(into: [RecordedEvent]()){
            guard !(try $1.event.record).eventType.hasPrefix("$") else {
                return
            }
            $0.append(try $1.event.record)
        }
        
        let responsedEventIds = allEvents.map { $0.id }
        
        let allSatisfy = events.allSatisfy { sourceEvent in
            responsedEventIds.contains(sourceEvent.id)
        }
        
        #expect(allSatisfy)

        try await client.deleteStream(streamIdentifier)
    }
    
    @Test(arguments: [
        [
            EventData(eventType: "AppendEvent-AccountCreated", model: ["Description": "Gears of War 4"]),
            EventData(eventType: "AppendEvent-AccountDeleted", model: ["Description": "Gears of War 4"]),
        ],
    ])
    func `It should succeed when read events from all streams start from appended position.`(events: [EventData]) async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: settings)
        
        let appendResponse = try await client.appendStream(streamIdentifier, events: events) {
            $0.revision(expected: .any)
        }

        let appendedPosition = try #require(appendResponse.position)
        let responses = try await client.readAllStreams(){
            $0.limit(1).forward().startFrom(position: .specified(commit: appendedPosition.commit, prepare: appendedPosition.prepare))
        }
        
        let allEvents = try await responses.reduce(into: [RecordedEvent]()){
            guard !(try $1.event.record).eventType.hasPrefix("$") else {
                return
            }
            $0.append(try $1.event.record)
        }
        
        let testEventIds = events.map{ $0.id }
        
        #expect(allEvents.contains(where: {
            testEventIds.contains($0.id)
        }))

        try await client.deleteStream(streamIdentifier)
    }

}
