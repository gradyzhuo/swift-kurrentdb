//
//  EventDataPayloadFormatTests.swift
//  KurrentCoreTests
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("EventData payload format")
struct EventDataPayloadFormatTests {
    @Test("A Data payload given as .json is stored as a base64 JSON string, like the removed init(payload: Codable) stored it")
    func jsonDataIsBase64String() throws {
        let bytes = Data([0x01, 0x02, 0x03])
        let event = EventData(eventType: "Snapshot", payload: .json(bytes))
        #expect(try event.payload.data == Data("\"AQID\"".utf8))
        #expect(event.payload.contentType == .json)
        // Multi-stream appends encode through EventRecord, which has its own JSONEncoder.
        #expect(try EventRecord(eventData: event).data == Data("\"AQID\"".utf8))
    }

    @Test("A Data payload given as data: is stored as the raw bytes")
    func rawDataIsRawBytes() throws {
        let bytes = Data([0x01, 0x02, 0x03])
        let event = EventData(eventType: "Snapshot", data: bytes)
        #expect(try event.payload.data == bytes)
    }
}
