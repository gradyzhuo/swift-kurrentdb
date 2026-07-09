//
//  PerCallCredentialsTests.swift
//  KurrentDB
//
//  Integration tests for per-call authentication override via `.authenticated(_:)`.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Per-call Credentials Tests", .serialized)
struct PerCallCredentialsTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    @Test("A per-call override with wrong credentials is rejected, without affecting client-level calls.")
    func testOverrideWithWrongCredentialsIsRejected() async throws {
        let client = KurrentDBClient(settings: settings)
        let streamName = UUID().uuidString
        let event = EventData(eventType: "PerCall-AccountCreated", model: ["k": "v"])

        // Client-level (correct) authentication works.
        _ = try await client.streams(specified: streamName)
            .append(events: [event]) { $0.expectedRevision = .any }

        // Overriding this single call with wrong credentials must be denied.
        await #expect(throws: KurrentError.self) {
            _ = try await client.streams(specified: streamName)
                .authenticated(.credentials(username: "admin", password: "definitely-wrong-password"))
                .append(events: [event]) { $0.expectedRevision = .any }
        }

        // The client-level authentication is unaffected and still works afterwards.
        _ = try await client.streams(specified: streamName)
            .append(events: [event]) { $0.expectedRevision = .any }

        try await client.streams(specified: streamName).delete()
    }

    @Test("authenticated(_:) returns a distinct instance and does not mutate the original facade.")
    func testAuthenticatedReturnsDistinctInstance() async throws {
        let client = KurrentDBClient(settings: settings)
        let base = client.streams(specified: UUID().uuidString)
        let scoped = base.authenticated(.credentials(username: "alice", password: "pw"))

        #expect(base.overrideCredentials == nil)
        #expect(scoped.overrideCredentials != nil)
        #expect(base !== scoped)
    }
}
