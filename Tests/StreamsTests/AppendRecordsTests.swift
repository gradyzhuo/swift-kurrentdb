//
//  AppendRecordsTests.swift
//  KurrentDB
//
//  Integration tests for v2 AppendRecords (Dynamic Consistency Boundary).
//  Requires a running KurrentDB 25.1+ instance.
//

import Foundation
@testable import KurrentDB
import Logging
import Testing

@Suite("AppendRecords (DCB) Tests", .serialized)
struct AppendRecordsTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func record(_ type: String, _ model: [String: String]) throws -> EventRecord {
        try EventRecord(eventType: type, payload: .json(model))
    }

    @Test("Appends records atomically across multiple streams and returns per-stream revisions.")
    func testMultiStreamAtomicAppend() async throws {
        let client = KurrentDBClient(settings: settings)
        let streamA = "orders-\(UUID().uuidString)"
        let streamB = "inventory-\(UUID().uuidString)"

        let response = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: streamA, records: try record("order-placed", ["id": "1"]), expectedRevision: .noStream),
            StreamEvent(stream: streamB, records: try record("stock-reserved", ["sku": "A"]), expectedRevision: .noStream),
        ])

        #expect(response.revisions.count == 2)
        #expect(response.revisions.contains { $0.streamIdentifier.name == streamA && $0.revision == 0 })
        #expect(response.revisions.contains { $0.streamIdentifier.name == streamB && $0.revision == 0 })

        try await client.streams(specified: streamA).delete()
        try await client.streams(specified: streamB).delete()
    }

    @Test("Enforces uniqueness via a .noStream check on the second append.")
    func testUniquenessViaNoStream() async throws {
        let client = KurrentDBClient(settings: settings)
        let uniqueStream = "user-email-\(UUID().uuidString)"

        // First registration succeeds.
        _ = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: uniqueStream, records: try record("email-registered", ["email": "a@x.com"]), expectedRevision: .noStream),
        ])

        // Second registration must fail because the stream now exists.
        await #expect(throws: KurrentError.self) {
            _ = try await client.multiStreams.appendRecords(events: [
                StreamEvent(stream: uniqueStream, records: try record("email-registered", ["email": "a@x.com"]), expectedRevision: .noStream),
            ])
        }

        try await client.streams(specified: uniqueStream).delete()
    }

    @Test("Cross-stream check: writes to one stream gated on another stream's revision.")
    func testCrossStreamConsistencyCheckViolation() async throws {
        let client = KurrentDBClient(settings: settings)
        let seat = "seat-\(UUID().uuidString)"
        let booking = "booking-\(UUID().uuidString)"

        // Establish the seat stream at revision 0.
        _ = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: seat, records: try record("seat-created", ["seat": "A1"]), expectedRevision: .noStream),
        ])

        // Move the seat forward so a stale check (expecting revision 0) will fail.
        _ = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: seat, records: try record("seat-held", ["by": "someone"]), expectedRevision: .at(0)),
        ])

        // Write to booking, but gated on seat still being at revision 0 (now stale) — must violate.
        do {
            _ = try await client.multiStreams.appendRecords(
                events: [StreamEvent(stream: booking, records: try record("seat-booked", ["by": "grady"]))],
                checks: [.streamState(seat, .at(0))]
            )
            Issue.record("Expected a consistency violation but the append succeeded.")
        } catch let KurrentError.consistencyViolation(violations) {
            #expect(!violations.isEmpty)
            #expect(violations.contains { $0.stream == seat })
        }

        try await client.streams(specified: seat).delete()
    }
}
