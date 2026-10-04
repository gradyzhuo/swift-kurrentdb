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

    private struct BodyError: Error, Equatable {}

    private func sharedRetainCount(_ client: KurrentDBClient) async throws -> Int? {
        let node = try await client.selector.select()
        return client.selector.connections.sharedEntrySnapshot(for: node.endpoint)?.retainCount
    }

    @Test("Scoped read returns the same events as read()")
    func scopedMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 50, to: stream)

        let buffered = try await stream.read().reduce(into: [UUID]()) { ids, response in
            ids.append(try response.event.record.id)
        }
        let scoped = try await stream.delivery(.scoped).read { events in
            try await events.reduce(into: [UUID]()) { ids, response in
                ids.append(try response.event.record.id)
            }
        }
        #expect(scoped == buffered)
        #expect(scoped.count == 50)
    }

    @Test("Breaking after the first event returns the lease, and production stays bounded")
    func earlyBreakReleasesLease() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "ScopedRead-\(UUID().uuidString)"
        let stream = client.streams(specified: name)
        try await appendEvents(count: 300, to: stream)

        let first = try await stream.delivery(.scoped).read { events -> UUID? in
            for try await response in events { return try response.event.record.id }
            return nil
        }
        #expect(first != nil)
        #expect(try await sharedRetainCount(client) == 0)

        // Bounded production, observed on the internal call.
        let node = try await client.selector.select()
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: name), options: .init())
        let call = try await usecase.open(node: node, callOptions: .defaults, credentials: nil)
        _ = try await call.handoff.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(call.handoff.sentCount - call.handoff.deliveredCount <= call.handoff.capacity)
        #expect(call.handoff.sentCount < 300)
        await call.close()
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("An error thrown by body reaches the caller unchanged and the lease is returned")
    func bodyErrorPropagates() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 10, to: stream)

        await #expect(throws: BodyError.self) {
            try await stream.delivery(.scoped).read { events in
                for try await _ in events { throw BodyError() }
            }
        }
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("Cancelling the caller's task while body iterates ends the read and returns the lease")
    func callerCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        let reader = Task {
            try await stream.delivery(.scoped).read { events in
                for try await _ in events {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        reader.cancel()
        _ = await reader.result
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("A stream that escapes body ends immediately when iterated later")
    func escapedStreamEnds() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 20, to: stream)

        let escaped = try await stream.delivery(.scoped).read { events in events }
        var count = 0
        for try await _ in escaped { count += 1 }
        #expect(count == 0)
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("Reading a missing stream fails the same way as read()")
    func missingStream() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-missing-\(UUID().uuidString)")

        var bufferedError: (any Error)?
        do { for try await _ in try await stream.read() {} } catch { bufferedError = error }
        var scopedError: (any Error)?
        do { try await stream.delivery(.scoped).read { events in for try await _ in events {} } } catch { scopedError = error }

        #expect(bufferedError != nil)
        #expect(scopedError.map { "\($0)" } == bufferedError.map { "\($0)" })
    }

    @Test("$all scoped read with a limit stops after the limit")
    func allStreamsScoped() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let count = try await client.allStreams.delivery(.scoped).read {
            $0.limit = 5
        } body: { events in
            try await events.reduce(0) { total, _ in total + 1 }
        }
        #expect(count == 5)
        #expect(try await sharedRetainCount(client) == 0)
    }
}
