//
//  AppendSessionTests.swift
//  KurrentDB
//
//  Integration tests for the v2 AppendSession (client.multiStreams.append).
//  Requires a running KurrentDB 25.1+ instance.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("AppendSession Tests", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_SUPPORTS_MULTI_STREAMS"] == "true"))
struct AppendSessionTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func record(_ type: String) throws -> EventRecord {
        try EventRecord(eventType: type, payload: .json(["k": "v"]))
    }

    @Test("AppendSession to a tombstoned stream throws resourceDeleted instead of a retried grpcError.")
    func testAppendToTombstonedStream() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = "tombstoned-\(UUID().uuidString)"
        _ = try await client.multiStreams.append(events: [
            StreamEvent(stream: stream, records: try record("created")),
        ])
        _ = try await client.streams(specified: stream).tombstone()

        await #expect(throws: KurrentError.resourceDeleted(resource: stream)) {
            _ = try await client.multiStreams.append(events: [
                StreamEvent(stream: stream, records: try record("after")),
            ])
        }
    }

    @Test("AppendSession sends the expected revision and reports a conflict as wrongExpectedVersion.")
    func testRevisionConflict() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = "session-conflict-\(UUID().uuidString)"
        _ = try await client.multiStreams.append(events: [
            StreamEvent(stream: stream, records: try record("created"), expectedRevision: .noStream),
        ])

        do {
            _ = try await client.multiStreams.append(events: [
                StreamEvent(stream: stream, records: try record("stale"), expectedRevision: .at(5)),
            ])
            Issue.record("Expected wrongExpectedVersion, but the append succeeded.")
        } catch let KurrentError.wrongExpectedVersion(expected, current) {
            guard case .revision(5) = expected, case .revision(0) = current else {
                Issue.record("Expected (5, 0), got (\(expected), \(current)).")
                return
            }
        }

        // A matching revision still appends.
        let response = try await client.multiStreams.append(events: [
            StreamEvent(stream: stream, records: try record("next"), expectedRevision: .at(0)),
        ])
        #expect(response.results.first?.currentRevision == 1)

        try await client.streams(specified: stream).delete()
    }
}
