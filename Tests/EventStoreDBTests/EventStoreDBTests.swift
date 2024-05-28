@testable import EventStoreDB
import Testing
import XCTest

final class EventStoreDBTests: XCTestCase {
    func testEventDataFromJSON() throws {
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest

        // Defining Test Cases and Test Methods
        // https://developer.apple.com/documentation/xctest/defining_test_cases_and_test_methods

        let jsonFileURL = Bundle.module.url(forResource: "multiple-events", withExtension: "json")
        let jsonData = try Data(contentsOf: jsonFileURL!)
        _ = try EventData.events(fromJSONData: jsonData)

//        try XCTAssertEqual(events, [
//            .init(id: .init(uuidString: "fbf4b1a1-b4a3-4dfe-a01f-ec52c34e16e4")!, eventType: "event-type", data: "test".data(using: .utf8)!, contentType: .json, customMetadata: nil),
//            .init(id: .init(uuidString: "0f9fad5b-d9cb-469f-a165-70867728951e")!, eventType: "event-type", data: "test".data(using: .utf8)!, contentType: .json, customMetadata: nil)
//        ])
    }
}
