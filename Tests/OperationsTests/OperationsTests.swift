//
//  OperationsTests.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/27.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Operations Tests", .serialized)
struct OperationsTests: Sendable {
    let settings: ClientSettings

    init() throws {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    // MARK: - Scavenge

    @Test("Start a scavenge returns a non-empty scavengeId.")
    func testStartScavenge() async throws {
        let client = KurrentDBClient(settings: settings)

        let response = try await client.operations(of: .scavenge)
            .startScavenge(threadCount: 1, startFromChunk: 0)

        #expect(!response.scavengeId.isEmpty)

        switch response.scavengeResult {
        case .started, .inProgress:
            break
        default:
            Issue.record("Unexpected scavenge result: \(response.scavengeResult)")
        }
    }

    @Test("Start then stop a scavenge returns a stopped result.")
    func testStopScavenge() async throws {
        let client = KurrentDBClient(settings: settings)

        let startResponse = try await client.operations(of: .scavenge)
            .startScavenge(threadCount: 1, startFromChunk: 0)
        let scavengeId = startResponse.scavengeId
        #expect(!scavengeId.isEmpty)

        let stopResponse = try await client.operations(of: .activeScavenge(scavengeId: scavengeId))
            .stopScavenge()

        switch stopResponse.scavengeResult {
        case .stopped, .inProgress:
            break
        default:
            Issue.record("Unexpected stop result: \(stopResponse.scavengeResult)")
        }
    }

    // MARK: - System Operations

    @Test("Merge indexes completes without error.")
    func testMergeIndexes() async throws {
        let client = KurrentDBClient(settings: settings)
        try await client.operations(of: .system).mergeIndexes()
    }

    @Test("Restart persistent subscriptions subsystem completes without error.")
    func testRestartPersistentSubscriptions() async throws {
        let client = KurrentDBClient(settings: settings)
        try await client.operations(of: .system).restartPersistentSubscriptions()
    }

    // MARK: - Node Operations

    @Test("Set node priority completes without error.")
    func testSetNodePriority() async throws {
        let client = KurrentDBClient(settings: settings)
        try await client.operations(of: .node).setNodePriority(priority: 0)
    }

    @Test("Resign node completes without error.")
    func testResignNode() async throws {
        let client = KurrentDBClient(settings: settings)
        // On a multi-node cluster, resigning causes a brief re-election.
        // The suite is serialized so subsequent tests wait for completion.
        try await client.operations(of: .node).resignNode()
    }
}
