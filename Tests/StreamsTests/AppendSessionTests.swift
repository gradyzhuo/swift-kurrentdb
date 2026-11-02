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
}
