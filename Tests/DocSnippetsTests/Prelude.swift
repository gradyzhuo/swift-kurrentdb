//
//  Prelude.swift
//  swift-kurrentdb
//
//  Names the documentation examples use without declaring them. The examples
//  themselves are compiled from DocSnippets.generated.swift, which
//  `scripts/generate-doc-snippets.py` writes; nothing here connects to a server.
//

import Foundation
import KurrentDB
import Testing

struct OrderPlaced: Codable, Sendable {
    var orderId: String
    var total: Double = 0
}

/// Placeholders the migration guide and README refer to by name.
let js = "fromAll().when({ $any: function(s, e) {} })"
struct MyResult: Codable {}
struct MyState: Codable {}

let settings = ClientSettings.localhost()
let client = KurrentDBClient(settings: settings)

let eventData = EventData(eventType: "OrderPlaced", model: OrderPlaced(orderId: "order-1"))
let event = eventData
let events = [eventData]
let record = try! EventRecord(eventType: "OrderPlaced", payload: .json(OrderPlaced(orderId: "order-1")))

@Test("Documentation examples compile")
func documentationExamplesCompile() {
    // Building this target is the check; see scripts/generate-doc-snippets.py.
}
