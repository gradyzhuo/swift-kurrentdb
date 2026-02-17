//
//  MonitoringTests.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/17.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Monitoring Tests", .serialized)
struct MonitoringTests: Sendable {
    let settings: ClientSettings

    init() throws {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    // MARK: - Stats
    @Test("It should retrieve server statistics.")
    func testStats() async throws {
        let client = KurrentDBClient(settings: settings)
        
        let stats = try await client.stats()
        var received = false

        for try await snapshot in stats {
            #expect(!snapshot.stats.isEmpty)
            received = true
            break // Only need the first snapshot
        }

        #expect(received)
    }

    @Test("It should retrieve stats with custom refresh interval.")
    func testStatsWithCustomRefresh() async throws {
        let client = KurrentDBClient(settings: settings)

        let stats = try await client.stats(refreshTimePeriodInMs: 5000)
        var received = false

        for try await snapshot in stats {
            #expect(!snapshot.stats.isEmpty)
            received = true
            break
        }

        #expect(received)
    }

    @Test("It should retrieve stats with metadata.")
    func testStatsWithMetadata() async throws {
        let client = KurrentDBClient(settings: settings)

        let stats = try await client.stats(useMetadata: true)
        var received = false

        for try await snapshot in stats {
            #expect(!snapshot.stats.isEmpty)
            received = true
            break
        }

        #expect(received)
    }
}
