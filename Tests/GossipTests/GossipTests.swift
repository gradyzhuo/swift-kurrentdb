//
//  GossipTests.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Gossip Tests", .serialized)
struct GossipTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    @Test("It should read gossip and return cluster member info.")
    func testReadGossip() async throws {
        let client = KurrentDBClient(settings: settings)
        let members = try await client.readGossip()

        #expect(!members.isEmpty)

        for member in members {
            #expect(member.isAlive)
            #expect(!member.httpEndPoint.host.isEmpty)
            #expect(member.httpEndPoint.port > 0)
        }
    }

    @Test("It should find at least one node with a known state.")
    func testReadGossipNodeStates() async throws {
        let client = KurrentDBClient(settings: settings)
        let members = try await client.readGossip()

        let knownStates: [Gossip.VNodeState] = [
            .leader, .follower, .readOnlyReplica, .clone,
            .catchingUp, .preLeader, .preReplica, .manager,
        ]

        let hasKnownState = members.contains { member in
            knownStates.contains(member.state)
        }
        #expect(hasKnownState)
    }

    @Test("It should read gossip with custom timeout.")
    func testReadGossipWithTimeout() async throws {
        let client = KurrentDBClient(settings: settings)
        let members = try await client.readGossip(timeout: .seconds(10))

        #expect(!members.isEmpty)
    }
}
