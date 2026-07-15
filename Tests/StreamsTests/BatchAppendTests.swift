//
//  BatchAppendTests.swift
//  KurrentDB
//
//  Integration tests for v1 BatchAppend (non-atomic, pipelined multi-stream append).
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("BatchAppend Tests", .serialized)
struct BatchAppendTests: Sendable {
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

    @Test("It pipelines appends to multiple different streams in one call.")
    func testMultiStreamBatchAppend() async throws {
        let client = KurrentDBClient(settings: settings)
        let streamA = "batch-a-\(UUID().uuidString)"
        let streamB = "batch-b-\(UUID().uuidString)"

        let response = try await client.multiStreams.batchAppend(events: [
            StreamEvent(stream: streamA, records: try record("a-created", ["k": "1"]), expectedRevision: .noStream),
            StreamEvent(stream: streamB, records: try record("b-created", ["k": "2"]), expectedRevision: .noStream),
        ])

        #expect(!response.hasFailures)
        #expect(response.results.count == 2)
        #expect(response.results[0].success?.streamIdentifier.name == streamA)
        #expect(response.results[1].success?.streamIdentifier.name == streamB)

        // Confirm both streams actually received the event.
        let aEvents = try await client.streams(specified: streamA).read().reduce(into: 0) { c, _ in c += 1 }
        let bEvents = try await client.streams(specified: streamB).read().reduce(into: 0) { c, _ in c += 1 }
        #expect(aEvents == 1)
        #expect(bEvents == 1)

        try await client.streams(specified: streamA).delete()
        try await client.streams(specified: streamB).delete()
    }

    @Test("It is non-atomic: a conflicting item fails while others succeed.")
    func testNonAtomicPartialFailure() async throws {
        let client = KurrentDBClient(settings: settings)
        let existing = "batch-existing-\(UUID().uuidString)"
        let fresh = "batch-fresh-\(UUID().uuidString)"

        // Make `existing` already exist so a `.noStream` expectation on it will conflict.
        _ = try await client.streams(specified: existing)
            .append(events: [EventData(eventType: "seed", model: ["k": "0"])]) { $0.expectedRevision = .any }

        let response = try await client.multiStreams.batchAppend(events: [
            StreamEvent(stream: existing, records: try record("should-fail", ["k": "x"]), expectedRevision: .noStream),
            StreamEvent(stream: fresh, records: try record("should-succeed", ["k": "y"]), expectedRevision: .noStream),
        ])

        #expect(response.hasFailures)
        // Item 0 (existing, .noStream) must fail; item 1 (fresh) must succeed.
        #expect(response.results[0].failure?.streamIdentifier.name == existing)
        #expect(response.results[1].success?.streamIdentifier.name == fresh)

        try await client.streams(specified: existing).delete()
        try await client.streams(specified: fresh).delete()
    }

    @Test("Results stay aligned with input order even when the same stream repeats.")
    func testResultOrderWithRepeatedStream() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = "batch-repeat-\(UUID().uuidString)"

        let response = try await client.multiStreams.batchAppend(events: [
            StreamEvent(stream: stream, records: try record("first", ["k": "1"]), expectedRevision: .noStream),
            StreamEvent(stream: stream, records: try record("second", ["k": "2"]), expectedRevision: .at(0)),
        ])

        #expect(response.results.count == 2)
        #expect(response.results.allSatisfy { $0.success != nil })

        try await client.streams(specified: stream).delete()
    }
}

private extension Streams.BatchAppend.Response.ItemResult {
    var success: Success? { if case let .success(s) = self { return s } else { return nil } }
    var failure: Failure? { if case let .failure(f) = self { return f } else { return nil } }
}
