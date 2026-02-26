//
//  ProjectionsAdvancedTests.swift
//  swift-kurrentdb
//
//  Integration tests for projection update, listing, and deletion verification.
//  Requires a running KurrentDB instance with projections enabled.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Projection Update & Listing Tests", .serialized)
struct ProjectionsAdvancedTests: Sendable {
    let client: KurrentDBClient

    init() {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        client = .init(settings: settings)
    }

    // MARK: - Update

    @Test("Update projection replaces the query without error")
    func testUpdateProjection() async throws {
        let name = "test_update_\(UUID())"
        let initial = "fromAll().outputState();"
        let updated = """
        fromAll()
            .when({
                $init: function() { return { count: 0 }; },
                $any: function(s, e) { s.count += 1; }
            })
            .outputState();
        """

        try await client.projections(of: .continuous(name: name)).create(query: initial)
        try await client.projections(of: NameTarget(name: name)).disable()

        try await client.projections(of: NameTarget(name: name)).update(query: updated)

        let detail = try #require(try await client.projections(of: NameTarget(name: name)).detail())
        #expect(detail.name == name)

        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    // MARK: - Listing

    @Test("Continuous projections list contains the newly created projection")
    func testListContinuousContainsNew() async throws {
        let name = "test_listContinuousAdv_\(UUID())"
        let projection = client.projections(of: .continuous(name: name))
        try await projection.create(query: "fromAll().outputState()")

        let projections = try await client.projections(of: .anyContinuous).list()
        #expect(projections.contains { $0.name == name })

        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    @Test("Deleted projection no longer appears in the continuous list")
    func testDeletedProjectionAbsentFromList() async throws {
        let name = "test_deleteVerify_\(UUID())"
        let projection = client.projections(of: .continuous(name: name))
        try await projection.create(query: "fromAll().outputState()")

        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }

        let projections = try await client.projections(of: .anyContinuous).list()
        #expect(!projections.contains { $0.name == name })
    }

    // MARK: - Detail

    @Test("getProjectionDetail returns correct mode and name")
    func testProjectionDetailMode() async throws {
        let name = "test_detailMode_\(UUID())"
        try await client.projections(of: .continuous(name: name)).create(query: "fromAll().outputState()")

        let detail = try #require(try await client.projections(of: NameTarget(name: name)).detail())
        #expect(detail.name == name)
        #expect(detail.mode == .continuous)

        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }

    // MARK: - Abort then reset
    @Test("Reset projection after abort transitions to Stopped state")
    func testAbortThenResetTransitionsToStopped() async throws {
        let name = "test_abortReset_\(UUID())"
        try await client.projections(of: .continuous(name: name)).create(query: "fromAll().outputState()")

        try await client.projections(of: NameTarget(name: name)).abort()
        let abortedDetail = try #require(try await client.projections(of: NameTarget(name: name)).detail())
        #expect(abortedDetail.status.contains(.aborted))

        try await client.projections(of: NameTarget(name: name)).reset()
        let resetDetail = try #require(try await client.projections(of: NameTarget(name: name)).detail())
        // After reset the projection enters Stopped (may then transition to Running)
        #expect(resetDetail.status.contains(.stopped) || resetDetail.status.contains(.running))

        try await client.projections(of: NameTarget(name: name)).disable()
        try await client.projections(of: NameTarget(name: name)).delete {
            $0.deleteStateStream = true
            $0.deleteEmittedStreams = true
            $0.deleteCheckpointStream = true
        }
    }
}
