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

@Suite("AppendRecords (DCB) Tests", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_SUPPORTS_APPEND_RECORDS"] == "true"))
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

    // MARK: - Deleted streams, revision conflicts and resent records

    /// A stream that existed and was tombstoned.
    private func tombstonedStream(_ client: KurrentDBClient) async throws -> String {
        let stream = "tombstoned-\(UUID().uuidString)"
        _ = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: stream, records: try record("created", ["k": "v"]), expectedRevision: .noStream),
        ])
        _ = try await client.streams(specified: stream).tombstone()
        return stream
    }

    @Test("AppendRecords to a tombstoned stream reports a consistency violation with actual state -6.")
    func testAppendRecordsToTombstonedStream() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = try await tombstonedStream(client)

        do {
            _ = try await client.multiStreams.appendRecords(events: [
                StreamEvent(stream: stream, records: try record("after", ["k": "v"]), expectedRevision: .noStream),
            ])
            Issue.record("Expected a consistency violation, but the append succeeded.")
        } catch let KurrentError.consistencyViolation(violations) {
            #expect(violations == [.init(checkIndex: 0, stream: stream, expectedState: -1, actualState: -6)])
        }
    }

    @Test("A tombstoned stream and a revision conflict in one AppendRecords request are reported together.")
    func testTombstoneAndConflictTogether() async throws {
        let client = KurrentDBClient(settings: settings)
        let tombstoned = try await tombstonedStream(client)
        let other = "conflict-\(UUID().uuidString)"
        _ = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: other, records: try record("created", ["k": "v"]), expectedRevision: .noStream),
        ])

        do {
            _ = try await client.multiStreams.appendRecords(events: [
                StreamEvent(stream: tombstoned, records: try record("after", ["k": "v"]), expectedRevision: .noStream),
                StreamEvent(stream: other, records: try record("stale", ["k": "v"]), expectedRevision: .at(5)),
            ])
            Issue.record("Expected a consistency violation, but the append succeeded.")
        } catch let KurrentError.consistencyViolation(violations) {
            #expect(violations.count == 2)
            #expect(violations.contains { $0.stream == tombstoned && $0.actualState == -6 })
            #expect(violations.contains { $0.stream == other && $0.expectedState == 5 && $0.actualState == 0 })
        }

        try await client.streams(specified: other).delete()
    }

    @Test("AppendRecords with .noStream recreates a soft-deleted stream after its last revision.")
    func testRecreateSoftDeletedStream() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = "soft-deleted-\(UUID().uuidString)"
        _ = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: stream, records: try record("a", [:]), try record("b", [:]), try record("c", [:]), expectedRevision: .noStream),
        ])
        _ = try await client.streams(specified: stream).delete()

        let response = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: stream, records: try record("recreated", [:]), expectedRevision: .noStream),
        ])
        #expect(response.revisions.first?.revision == 3)

        try await client.streams(specified: stream).delete()
    }

    @Test("Resending AppendRecords with the same record ids is idempotent, even with .noStream.")
    func testResendSameRecordIds() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = "idempotent-\(UUID().uuidString)"
        let ids = [UUID(), UUID()]
        let events = { () throws -> [StreamEvent] in
            [StreamEvent(stream: stream, records: try ids.map {
                try EventRecord(id: $0, eventType: "e", payload: .json(["k": "v"]))
            }, expectedRevision: .noStream)]
        }

        let first = try await client.multiStreams.appendRecords(events: events())
        let second = try await client.multiStreams.appendRecords(events: events())
        #expect(first.revisions.first?.revision == 1)
        #expect(second.revisions.first?.revision == 1)
        #expect(second.position == first.position)

        var count = 0
        for try await _ in try await client.streams(specified: stream).read() {
            count += 1
        }
        #expect(count == 2)

        try await client.streams(specified: stream).delete()
    }

    struct OperatorMetadata: Codable, Equatable, Sendable {
        struct Origin: Codable, Equatable, Sendable {
            let service: String
            let tags: [String]
        }

        let operatorId: String
        let attempt: Int
        let negative: Int
        let ratio: Double
        let isRetry: Bool
        let issuedAt: Date
        let note: String?
        let origin: Origin
    }

    @Test("Custom metadata written through AppendRecords reads back through the v1 read unchanged.")
    func testCustomMetadataRoundTrip() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = "metadata-\(UUID().uuidString)"
        let metadata = OperatorMetadata(
            operatorId: "op-1", attempt: 3, negative: -42, ratio: 0.25, isRetry: true,
            issuedAt: Date(), note: nil,
            origin: .init(service: "billing", tags: ["a", "b"])
        )
        let recordId = UUID()
        let record = try EventRecord(
            id: recordId, eventType: "operator-acted", payload: .json(["k": "v"]),
            customMetadata: JSONEncoder().encode(metadata)
        )

        _ = try await client.multiStreams.appendRecords(events: [
            StreamEvent(stream: stream, records: record, expectedRevision: .noStream),
        ])

        let responses = try await client.streams(specified: stream).read()
        let first = try await responses.first { _ in true }
        guard case let .event(readEvent) = first else {
            Issue.record("Expected an event, got \(String(describing: first)).")
            return
        }
        let recorded = readEvent.record
        #expect(recorded.id == recordId)
        #expect(recorded.eventType == "operator-acted")
        #expect(recorded.contentType == .json)
        #expect(try JSONDecoder().decode(OperatorMetadata.self, from: recorded.customMetadata) == metadata)

        try await client.streams(specified: stream).delete()
    }
}
