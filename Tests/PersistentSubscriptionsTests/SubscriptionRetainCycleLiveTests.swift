//
//  SubscriptionRetainCycleLiveTests.swift
//  swift-kurrentdb
//
// Regression tests for issue #127, all through the real subscribe() → Read.send path (not by building a
// Subscription directly: that goes around the read task that held it strongly, which is why
// SubscriptionLifecycleTests could not catch the cycle). They need the 3-node cluster of server/docker-compose.yaml.
//
// Two points of observation:
// - The client: the number of dedicated connections registered in ConnectionProvider (a persistent
//   subscription is an RPC with a streamed response, one connection per subscription).
// - The server: getInfo().connections, the number of consumers the server believes are connected.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Persistent subscription retain cycle (#127, live)", .serialized, .timeLimit(.minutes(2)))
struct SubscriptionRetainCycleLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func event(_ tag: String) -> EventData {
        EventData(eventType: "RetainCycle-\(tag)", model: ["tag": tag])
    }

    /// Waits until the condition holds or the time runs out. Only for waiting on asynchronous teardown (release →
    /// onTermination → cancel → the server noticing the disconnect, each step timed by scheduling and the network).
    private func eventually(timeout: Duration = .seconds(15), _ condition: () async throws -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try await condition()
    }

    @Test("Dropping a handle that was never iterated closes the connection (a named stream)")
    func droppingUniteratedSpecifiedSubscriptionClosesConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let group = "retain-cycle-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(stream: "RetainCycle-\(UUID().uuidString)", group: group)
        try await persistent.create()

        do {
            // events is not iterated on purpose; nobody holds the handle once this scope ends.
            let subscription = try await persistent.subscribe()

            // Precondition: the connection is open before the drop, registered on the client and visible as a consumer on the server.
            // Without this step, a subscribe that never connected would also pass the assertions below.
            #expect(try await eventually { subscription.subscriptionId != nil })   // the server has confirmed this subscription
            #expect(client.selector.connections.activeDedicatedConnectionCount == 1)
            #expect(try await eventually { try await persistent.getInfo().connections.count == 1 })
        }

        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        #expect(try await eventually { try await persistent.getInfo().connections.isEmpty })

        try await persistent.delete()
    }

    @Test("Dropping a handle that was never iterated closes the connection ($all)")
    func droppingUniteratedAllStreamSubscriptionClosesConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let group = "retain-cycle-all-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(of: .allStreams(group: group))
        try await persistent.create()

        do {
            let subscription = try await persistent.subscribe()

            // Precondition: the connection is open before the drop.
            #expect(try await eventually { subscription.subscriptionId != nil })   // the server has confirmed this subscription
            #expect(client.selector.connections.activeDedicatedConnectionCount == 1)
            #expect(try await eventually { try await persistent.getInfo().connections.count == 1 })
        }

        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        #expect(try await eventually { try await persistent.getInfo().connections.isEmpty })

        try await persistent.delete()
    }

    /// The case the issue asks for: iterating events without holding the handle. With the cycle fixed the
    /// handle is released once events is taken, and no event may be lost on the way; teardown runs when events is released.
    @Test("Holding only events, not the handle, loses no event on the way")
    func iteratingEventsWithoutHoldingHandleDeliversEverything() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let streamName = "RetainCycle-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(stream: streamName, group: "retain-cycle-\(UUID().uuidString)")
        try await persistent.create()

        let expected = (0 ..< 5).map { "e\($0)" }
        var received: [String] = []
        do {
            // Keep only events; nobody holds the handle subscribe() returned.
            let events = try await persistent.subscribe().events

            for tag in expected {
                _ = try await client.streams(specified: streamName).append(events: [event(tag)]) {
                    $0.expectedRevision = .any
                }
            }

            for try await result in events {
                received.append(result.event.record.eventType)
                if received.count == expected.count { break }
            }
        }
        #expect(received == expected.map { "RetainCycle-\($0)" })

        // Once events leaves the scope the connection closes. (A break alone does not: see Subscription's documentation.)
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })

        try await client.streams(specified: streamName).delete()
        try await persistent.delete()
    }

    /// The ordinary use: hold the handle, iterate, ack, leave the loop; teardown runs when the handle is released.
    @Test("The ordinary use, holding the handle, works as before, with teardown when the handle is released")
    func holdingHandleStillWorksAndTearsDown() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let streamName = "RetainCycle-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(stream: streamName, group: "retain-cycle-\(UUID().uuidString)")
        try await persistent.create()

        var receivedType: String?
        do {
            let subscription = try await persistent.subscribe()
            _ = try await client.streams(specified: streamName).append(events: [event("held")]) {
                $0.expectedRevision = .any
            }

            for try await result in subscription.events {
                try await subscription.ack(readEvents: result.event)
                receivedType = result.event.record.eventType
                break
            }

            // While the handle is held, a break does not close the connection.
            #expect(client.selector.connections.activeDedicatedConnectionCount == 1)
        }
        #expect(receivedType == "RetainCycle-held")

        // Once the handle leaves the scope the connection closes.
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        #expect(try await eventually { try await persistent.getInfo().connections.isEmpty })

        try await client.streams(specified: streamName).delete()
        try await persistent.delete()
    }
}
