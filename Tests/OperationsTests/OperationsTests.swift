//
//  OperationsTests.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/27.
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Testing

// Six short admin RPCs; a hang here cost a full 30-minute job timeout on CI (run 37438212406)
// with no output to say which test it was. The time limit names the test and ends the step.
@Suite("Operations Tests", .serialized, .timeLimit(.minutes(2)))
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

    /// On a near-empty database a scavenge completes within ~150 ms, so stopping it right after
    /// starting races its completion, and the server's answer inside that window is not stable:
    /// CI run 37559453261 never answered the stop (the suite hit its time limit), run 37561720849
    /// answered the retry with `notFound` ("Scavenge id was invalid"), while locally a stop of an
    /// already-completed id returns `stopped`. The test therefore bounds the call with a deadline,
    /// retries once, and accepts every outcome that means "the stop reached the server and the
    /// scavenge is no longer running". The wiring of the RPC itself is pinned by the unknown-id
    /// test below, which does not depend on timing.
    @Test("Start then stop a scavenge leaves no running scavenge.")
    func testStopScavenge() async throws {
        var options = CallOptions.defaults
        options.timeout = .seconds(10)
        let client = KurrentDBClient(settings: settings, defaultCallOptions: options)

        let startResponse = try await client.operations(of: .scavenge)
            .startScavenge(threadCount: 1, startFromChunk: 0)
        let scavengeId = startResponse.scavengeId
        #expect(!scavengeId.isEmpty)

        let scavenge = client.operations(of: .activeScavenge(scavengeId: scavengeId))
        do throws(KurrentError) {
            let stopResponse = try await retryingOnDeadline { () async throws(KurrentError) in
                try await scavenge.stopScavenge()
            }
            switch stopResponse.scavengeResult {
            case .stopped, .inProgress:
                break
            default:
                Issue.record("Unexpected stop result: \(stopResponse.scavengeResult)")
            }
        } catch .resourceNotFound {
            // The scavenge completed between the start and the (retried) stop.
        }
    }

    @Test("Stopping an unknown scavenge id reports resourceNotFound.")
    func testStopUnknownScavenge() async throws {
        let client = KurrentDBClient(settings: settings)
        let unknown = client.operations(of: .activeScavenge(scavengeId: UUID().uuidString.lowercased()))
        do throws(KurrentError) {
            _ = try await unknown.stopScavenge()
            Issue.record("stopScavenge on an unknown id returned instead of throwing")
        } catch .resourceNotFound {
            // expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    /// Runs `operation` again once if the first attempt timed out at the call deadline.
    private func retryingOnDeadline<T>(_ operation: () async throws(KurrentError) -> T) async throws(KurrentError) -> T {
        do throws(KurrentError) {
            return try await operation()
        } catch .deadlineExceeded {
            return try await operation()
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
