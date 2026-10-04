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

        // RPC A is a live subscription from the start of the stream: the server can never finish it,
        // so it stays in flight until cancelled.
        var options = Streams<SpecifiedStream>.Subscribe.Options()
        options.revision = .start
        let request = ClientRequest(
            message: try Streams<SpecifiedStream>.Subscribe(from: .init(name: name), options: options).requestMessage(),
            metadata: try Metadata(from: node.settings)
        )

        // A signals once its first event arrived, then keeps draining until cancelled.
        let (firstEvent, firstEventSignal) = AsyncStream<Void>.makeStream()
        let parked = Task {
            let service = Streams<SpecifiedStream>.UnderlyingClient(wrapping: lease.client)
            try await service.read(request: request) { response in
                var signalled = false
                for try await message in response.messages {
                    if !signalled, case .event = message.content {
                        signalled = true
                        firstEventSignal.yield()
                        firstEventSignal.finish()
                    }
                }
            }
        }

        // Wait (bounded) until A is provably in flight and has received data.
        let arrived = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in firstEvent { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        try #require(arrived, "RPC A never received its first event")

        // RPC B runs on the same shared connection while A is in flight, and again after A is cancelled.
        let before = try await stream.read().reduce(0) { count, _ in count + 1 }
        parked.cancel()
        let outcome = await parked.result
        let after = try await stream.read().reduce(0) { count, _ in count + 1 }

        // A must have ended by cancellation, not by completing or an unrelated failure.
        switch outcome {
        case .success:
            Issue.record("RPC A finished normally; expected it to be cancelled")
        case let .failure(error):
            let cancelled = error is CancellationError || (error as? RPCError)?.code == .cancelled
            #expect(cancelled, "unexpected error for cancelled RPC A: \(error)")
        }

        #expect(before == 200)
        #expect(after == 200)
        #expect(client.selector.connections.createdSharedConnectionCount == createdBefore)
    }
}
