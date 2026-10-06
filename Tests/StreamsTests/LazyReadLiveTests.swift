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
    func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
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

    @Test("lazy returns the same events as read() and as buffered")
    func lazyMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 50, to: stream)

        let viaRead = try await stream.read().reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        let viaBuffered = try await stream.read().buffered.reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        let viaLazy = try await stream.read().lazy.reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        #expect(viaLazy == viaRead)
        #expect(viaBuffered == viaRead)
        #expect(viaLazy.count == 50)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("Breaking after the first event returns the lease and production stays bounded")
    func earlyBreakReleasesLease() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        var iterator = stream.read().lazy.makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first != nil)
        #expect(try await sharedRetainCount(client) == 1)             // positive control: the lease is held
        try await Task.sleep(for: .milliseconds(500))
        // The RPC task feeds a capacity-1 hand-off; nothing is pulled, so production has stalled.
        // Observe the hand-off counters through a separately opened ScopedCall, since the iterator's own call is private.
        let node = try await client.selector.select()
        let usecase = Streams<SpecifiedStream>.Read(from: stream.identifier, options: .init())
        let call = try await usecase.open(node: node, callOptions: .defaults, credentials: nil)
        _ = try await call.handoff.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(call.handoff.sentCount - call.handoff.deliveredCount <= call.handoff.capacity)
        #expect(call.handoff.sentCount < 300)
        await call.close()

        iterator = stream.read().lazy.makeAsyncIterator()   // release the first iterator → its RPC ends
        _ = iterator
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("A Lazy value can be iterated twice; each iteration is its own RPC")
    func lazyIsReiterable() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 20, to: stream)
        let lazy = stream.read().lazy

        var firstRun = 0
        for try await _ in lazy { firstRun += 1; if firstRun == 3 { break } }
        var secondRun = 0
        for try await _ in lazy { secondRun += 1 }
        #expect(firstRun == 3)
        #expect(secondRun == 20)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("Cancelling the iterating task throws CancellationError and returns the lease")
    func callerCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        let (firstElement, signal) = AsyncStream.makeStream(of: Void.self)
        let reader = Task {
            defer { signal.finish() }
            var count = 0
            for try await _ in stream.read().lazy {
                count += 1
                if count == 1 { signal.yield() }
                try? await Task.sleep(for: .milliseconds(50))   // non-throwing wait: cancellation must come from the SDK
            }
            return count
        }
        for await _ in firstElement { break }
        reader.cancel()
        await #expect(throws: CancellationError.self) { _ = try await reader.value }
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("A missing stream fails during iteration with the same error as read(), then ends")
    func missingStreamMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-missing-\(UUID().uuidString)")

        var bufferedError: (any Error)?
        do { for try await _ in try await stream.read() {} } catch { bufferedError = error }

        var lazyError: (any Error)?
        let iterator = stream.read().lazy.makeAsyncIterator()
        do { _ = try await iterator.next() } catch { lazyError = error }
        let afterError = try await iterator.next()

        #expect(bufferedError != nil)
        #expect(lazyError.map { "\($0)" } == bufferedError.map { "\($0)" })
        #expect(afterError == nil)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("Wrong credentials fail at the first next(), before any element")
    func wrongCredentials() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 5, to: stream)

        let unauthorised = stream.authenticated(.credentials(username: "admin", password: "wrong-password"))
        var count = 0
        await #expect(throws: KurrentError.self) {
            for try await _ in unauthorised.read().lazy { count += 1 }
        }
        #expect(count == 0)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("$all lazy read honours the limit")
    func allStreamsLazy() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let count = try await client.allStreams.read { $0.limit = 5 }.lazy.reduce(0) { total, _ in total + 1 }
        #expect(count == 5)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("After shutdown, the first next() throws connectionClosed")
    func afterShutdown() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 1, to: stream)
        try client.shutdown()
        await #expect(throws: KurrentError.connectionClosed) {
            for try await _ in stream.read().lazy {}
        }
    }

    @Test("Cancelling one lazy read leaves a concurrent read on the shared connection intact")
    func cancellingLazyKeepsSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)
        let createdBefore = client.selector.connections.createdSharedConnectionCount

        let (firstElement, signal) = AsyncStream.makeStream(of: Void.self)
        let reader = Task {
            defer { signal.finish() }
            var count = 0
            for try await _ in stream.read().lazy {
                count += 1
                if count == 1 { signal.yield() }
                try? await Task.sleep(for: .milliseconds(50))   // non-throwing: cancellation must come from the SDK
            }
            return count
        }
        let arrived = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in firstElement { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        try #require(arrived, "the lazy read never produced its first element")

        let before = try await stream.read().reduce(0) { n, _ in n + 1 }
        reader.cancel()
        await #expect(throws: CancellationError.self) { _ = try await reader.value }
        let after = try await stream.read().reduce(0) { n, _ in n + 1 }

        #expect(before == 300)
        #expect(after == 300)
        #expect(client.selector.connections.createdSharedConnectionCount == createdBefore)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    /// A `Streams` value whose every call carries the given deadline.
    func streams(_ client: KurrentDBClient, name: String, timeout: Duration) -> Streams<SpecifiedStream> {
        var options = CallOptions.defaults
        options.timeout = timeout
        return Streams<SpecifiedStream>(target: .specified(name), selector: client.selector, callOptions: options)
    }

    @Test("An RPC deadline surfaces as the RPC's error, not CancellationError, for an idle lazy consumer")
    func deadlineIsNotCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "LazyRead-Deadline-\(UUID().uuidString)"
        try await appendEvents(count: 300, to: client.streams(specified: name))
        let timed = streams(client, name: name, timeout: .seconds(1))

        let iterator = timed.read().lazy.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .seconds(2))   // the producer is suspended in send; the deadline expires
        var failure: (any Error)?
        do { while try await iterator.next() != nil {} } catch { failure = error }

        let error = try #require(failure)
        #expect(!(error is CancellationError))
        // Post-acceptance errors reach the iterator as the RPC's own error, like a buffered read's stream.
        #expect((error as? RPCError)?.code == .deadlineExceeded)
    }

    @Test("A subscription whose deadline expires while its consumer is idle ends with the deadline error")
    func subscriptionDeadlineIsNotCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "LazyRead-SubDeadline-\(UUID().uuidString)"
        try await appendEvents(count: 300, to: client.streams(specified: name))
        let timed = streams(client, name: name, timeout: .seconds(1))

        let subscription = try await timed.subscribe { $0.revision = .start }
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .seconds(2))
        var failure: (any Error)?
        do { while try await iterator.next() != nil {} } catch { failure = error }

        let error = try #require(failure)
        #expect(!(error is CancellationError))
        #expect((error as? RPCError)?.code == .deadlineExceeded)
    }
}
