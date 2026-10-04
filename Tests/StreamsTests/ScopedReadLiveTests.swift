//
//  ScopedReadLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml.
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Testing

@Suite("Scoped read (live)", .serialized, .timeLimit(.minutes(3)))
struct ScopedReadLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func event(_ type: String = "ScopedRead-Test") -> EventData {
        EventData(eventType: type, model: ["Description": "scoped read"])
    }

    /// Waits until the condition holds or the timeout passes.
    private func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func appendEvents(count: Int, to stream: Streams<SpecifiedStream>) async throws {
        _ = try await stream.append(events: (0 ..< count).map { _ in event() }) { $0.expectedRevision = .any }
    }

    @Test("Cancelling one server-streaming RPC does not disturb another on the same shared connection")
    func cancellingOneRPCKeepsSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "ScopedRead-Spike-\(UUID().uuidString)"
        let stream = client.streams(specified: name)
        try await appendEvents(count: 200, to: stream)

        let node = try await client.selector.select()
        let createdBefore = client.selector.connections.createdSharedConnectionCount
        let lease = try node.connections.acquire(node.endpoint)
        defer { lease.release() }

        let request = ClientRequest(
            message: try Streams<SpecifiedStream>.Read(from: .init(name: name), options: .init()).requestMessage(),
            metadata: try Metadata(from: node.settings)
        )

        // RPC A: read one message, then park until cancelled.
        let parked = Task {
            let service = Streams<SpecifiedStream>.UnderlyingClient(wrapping: lease.client)
            try await service.read(request: request) { response in
                var iterator = response.messages.makeAsyncIterator()
                _ = try await iterator.next()
                try await Task.sleep(for: .seconds(60))
            }
        }

        // RPC B runs on the same shared connection while A is parked, and again after A is cancelled.
        let before = try await stream.read().reduce(0) { count, _ in count + 1 }
        parked.cancel()
        _ = await parked.result
        let after = try await stream.read().reduce(0) { count, _ in count + 1 }

        #expect(before == 200)
        #expect(after == 200)
        #expect(client.selector.connections.createdSharedConnectionCount == createdBefore)
    }
}
