//
//  AllStreamsTests.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2023/10/28.
//

import Foundation
@testable import KurrentDB
import Logging
import Testing

@Suite("The tests of AllStream", .serialized)
struct AllStreamsTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    @Test("It should succeed when read events from all streams without configuation.", arguments: [
        [
            EventData(eventType: "AppendEvent-AccountCreated", model: ["Description": "Gears of War 4"]),
            EventData(eventType: "AppendEvent-AccountDeleted", model: ["Description": "Gears of War 4"]),
        ],
    ])
    func testReadWithoutConfiguration(events: [EventData]) async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: settings)

        let _ = try await client.appendStream(streamIdentifier, events: events) {
            $0.revision(expected: .any)
        }

        let responses = try await client.readAllStreams()

        let allEvents = try await responses.reduce(into: [RecordedEvent]()) {
            guard try !($1.event.record).eventType.hasPrefix("$") else {
                return
            }
            try $0.append($1.event.record)
        }

        let responsedEventIds = allEvents.map(\.id)

        let allSatisfy = events.allSatisfy { sourceEvent in
            responsedEventIds.contains(sourceEvent.id)
        }

        #expect(allSatisfy)

        try await client.deleteStream(streamIdentifier)
    }

    @Test("It should succeed when read events from all streams start from appended position.", arguments: [
        [
            EventData(eventType: "AppendEvent-AccountCreated", model: ["Description": "Gears of War 4"]),
            EventData(eventType: "AppendEvent-AccountDeleted", model: ["Description": "Gears of War 4"]),
        ],
    ])
    func testReadAllFromAppendedPosition(events: [EventData]) async throws {
        let streamIdentifier = StreamIdentifier(name: UUID().uuidString)
        let client = KurrentDBClient(settings: settings)

        let appendResponse = try await client.appendStream(streamIdentifier, events: events) {
            $0.revision(expected: .any)
        }

        let appendedPosition = try #require(appendResponse.position)
        let responses = try await client.readAllStreams {
            $0.limit(1).forward().startFrom(position: .specified(commit: appendedPosition.commit, prepare: appendedPosition.prepare))
        }

        let allEvents = try await responses.reduce(into: [RecordedEvent]()) {
            guard try !($1.event.record).eventType.hasPrefix("$") else {
                return
            }
            try $0.append($1.event.record)
        }

        let testEventIds = events.map(\.id)

        #expect(allEvents.contains(where: {
            testEventIds.contains($0.id)
        }))

        try await client.deleteStream(streamIdentifier)
    }
}
