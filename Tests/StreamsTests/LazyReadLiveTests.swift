//
//  LazyReadLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml.
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Testing

@Suite("Lazy read (live)", .serialized, .timeLimit(.minutes(3)))
struct LazyReadLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    func event(_ type: String = "LazyRead-Test") -> EventData {
        EventData(eventType: type, model: ["Description": "lazy read"])
    }

    /// Waits until the condition holds or the timeout passes. Lease release after a lazy read
    /// happens in the iterator's deinit, asynchronously, so tests poll for it.
    func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func appendEvents(count: Int, to stream: Streams<SpecifiedStream>) async throws {
        _ = try await stream.append(events: (0 ..< count).map { _ in event() }) { $0.expectedRevision = .any }
    }

    /// Retain count of the shared connection the client is currently routed to.
    func sharedRetainCount(_ client: KurrentDBClient) async throws -> Int? {
        let node = try await client.selector.select()
        return client.selector.connections.sharedEntrySnapshot(for: node.endpoint)?.retainCount
    }

    @Test("Cancelling one in-flight server-streaming RPC does not disturb another on the same shared connection")
    func cancellingOneRPCKeepsSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "LazyRead-Spike-\(UUID().uuidString)"
        let stream = client.streams(specified: name)
        try await appendEvents(count: 200, to: stream)

        let node = try await client.selector.select()
        let createdBefore = client.selector.connections.createdSharedConnectionCount
        let lease = try node.connections.acquire(node.endpoint)
        defer { lease.release() }

        // RPC A: a live subscription from the start — the server can never finish it.
        var subscribeOptions = Streams<SpecifiedStream>.Subscribe.Options()
        subscribeOptions.revision = .start
        let request = ClientRequest(
            message: try Streams<SpecifiedStream>.Subscribe(from: .init(name: name), options: subscribeOptions).requestMessage(),
            metadata: try Metadata(from: node.settings)
        )
        let (firstEvent, firstEventSignal) = AsyncStream.makeStream(of: Void.self)
        let parked = Task {
            defer { firstEventSignal.finish() }
            let service = Streams<SpecifiedStream>.UnderlyingClient(wrapping: lease.client)
            try await service.read(request: request) { response in
                // Keep draining: a subscription never ends on its own, so only cancelling the
                // task ends this loop, and the cancellation must surface through the RPC path.
                var signalled = false
                for try await message in response.messages {
                    if !signalled, case .event = message.content {
                        signalled = true
                        firstEventSignal.yield()
                    }
                }
            }
        }
        defer { parked.cancel() }

        // Wait until A is provably in flight (bounded).
        let arrived = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in firstEvent { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        try #require(arrived, "RPC A never received its first event")

        // RPC B on the same shared connection, while A is parked and again after A is cancelled.
        let before = try await stream.read().reduce(0) { count, _ in count + 1 }
        parked.cancel()
        let outcome = await parked.result
        let after = try await stream.read().reduce(0) { count, _ in count + 1 }

        switch outcome {
        case .success:
            Issue.record("RPC A ended without being cancelled")
        case let .failure(error):
            let cancelled = error is CancellationError || (error as? RPCError)?.code == .cancelled
            #expect(cancelled, "RPC A ended with \(error) instead of cancellation")
        }
        #expect(before == 200)
        #expect(after == 200)
        #expect(client.selector.connections.createdSharedConnectionCount == createdBefore)
    }
}
