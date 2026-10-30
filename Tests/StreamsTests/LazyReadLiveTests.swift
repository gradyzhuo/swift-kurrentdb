//
//  LazyReadLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml.
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Synchronization
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

    /// Retain count of the shared read connection (the one lazy reads use) of the node the client
    /// is currently routed to.
    func readRetainCount(_ client: KurrentDBClient) async throws -> Int? {
        let node = try await client.selector.select()
        return client.selector.connections.readEntrySnapshot(for: node.endpoint)?.retainCount
    }

    @Test("Cancelling one in-flight server-streaming RPC does not disturb another on the same shared connection")
    func cancellingOneRPCKeepsSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
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
        let before = try await stream.read().buffered.reduce(0) { count, _ in count + 1 }
        parked.cancel()
        let outcome = await parked.result
        let after = try await stream.read().buffered.reduce(0) { count, _ in count + 1 }

        switch outcome {
        case .success:
            Issue.record("RPC A ended without being cancelled")
        case let .failure(error):
            // A raw grpc-swift call, not a KurrentDB read: cancelling its task surfaces as CancellationError.
            #expect(error is CancellationError, "RPC A ended with \(error) instead of cancellation")
        }
        #expect(before == 200)
        #expect(after == 200)
        #expect(client.selector.connections.createdSharedConnectionCount == createdBefore)
    }

    @Test("read() returns the same events as buffered")
    func lazyMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 50, to: stream)

        let viaRead = try await stream.read().reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        let viaBuffered = try await stream.read().buffered.reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        #expect(viaBuffered == viaRead)
        #expect(viaRead.count == 50)
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("Breaking after the first event returns the lease and production stays bounded")
    func earlyBreakReleasesLease() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        var iterator = stream.read().makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first != nil)
        #expect(try await readRetainCount(client) == 1)             // positive control: the lease is held
        try await Task.sleep(for: .milliseconds(500))
        // The RPC task feeds a rendezvous hand-off; nothing is pulled, so the producer is parked on the second element.
        // Observe the hand-off counters through a separately opened ScopedCall, since the iterator's own call is private.
        let node = try await client.selector.select()
        let usecase = Streams<SpecifiedStream>.Read(from: stream.identifier, options: .init())
        let call = try await usecase.open(node: node, callOptions: .defaults, credentials: nil)
        _ = try await call.handoff.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(call.handoff.isProducerWaiting)
        #expect(call.handoff.deliveredCount == 1)
        await call.close()

        iterator = stream.read().makeAsyncIterator()   // release the first iterator → its RPC ends
        _ = iterator
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("A ReadCall can be iterated twice; each iteration is its own RPC")
    func lazyIsReiterable() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 20, to: stream)
        let call = stream.read()

        var firstRun = 0
        for try await _ in call { firstRun += 1; if firstRun == 3 { break } }
        var secondRun = 0
        for try await _ in call { secondRun += 1 }
        #expect(firstRun == 3)
        #expect(secondRun == 20)
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("Cancelling the iterating task throws CancellationError and returns the lease")
    func callerCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        let (firstElement, signal) = AsyncStream.makeStream(of: Void.self)
        let reader = Task {
            defer { signal.finish() }
            var count = 0
            for try await _ in stream.read() {
                count += 1
                if count == 1 { signal.yield() }
                try? await Task.sleep(for: .milliseconds(50))   // non-throwing wait: cancellation must come from the SDK
            }
            return count
        }
        for await _ in firstElement { break }
        reader.cancel()
        await #expect(throws: CancellationError.self) { _ = try await reader.value }
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("A missing stream fails during iteration with the same error as read(), then ends")
    func missingStreamMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-missing-\(UUID().uuidString)")

        var bufferedError: (any Error)?
        do { for try await _ in try await stream.read().buffered {} } catch { bufferedError = error }

        var lazyError: (any Error)?
        let iterator = stream.read().makeAsyncIterator()
        do { _ = try await iterator.next() } catch { lazyError = error }
        let afterError = try await iterator.next()

        #expect(bufferedError != nil)
        #expect(lazyError.map { "\($0)" } == bufferedError.map { "\($0)" })
        #expect(afterError == nil)
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("Wrong credentials fail at the first next(), before any element")
    func wrongCredentials() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 5, to: stream)

        let unauthorised = stream.authenticated(.credentials(username: "admin", password: "wrong-password"))
        var count = 0
        await #expect(throws: KurrentError.self) {
            for try await _ in unauthorised.read() { count += 1 }
        }
        #expect(count == 0)
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("$all lazy read honours the limit")
    func allStreamsLazy() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let count = try await client.allStreams.read { $0.limit = 5 }.reduce(0) { total, _ in total + 1 }
        #expect(count == 5)
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("After shutdown, the first next() throws connectionClosed")
    func afterShutdown() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 1, to: stream)
        client.shutdown()
        await #expect(throws: KurrentError.connectionClosed) {
            for try await _ in stream.read() {}
        }
    }

    /// The lazy twin of `ConnectionReuseLiveTests.shutdownDuringReadEndsIteration`: there the read
    /// only has to end; here it must end with `connectionClosed`, not read on or fail as a transport error.
    @Test("A lazy read in progress on the read connection during shutdown() ends with connectionClosed")
    func shutdownDuringLazyRead() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 2000, to: stream)

        let (firstElement, signal) = AsyncStream.makeStream(of: Void.self)
        let reader = Task { () -> (count: Int, error: (any Error)?) in
            defer { signal.finish() }
            var count = 0
            do {
                for try await _ in stream.read() {
                    count += 1
                    if count == 1 { signal.yield() }
                    try? await Task.sleep(for: .milliseconds(1))   // keep the read in progress past the shutdown
                }
                return (count, nil)
            } catch {
                return (count, error)
            }
        }
        for await _ in firstElement { break }
        try await Task.sleep(for: .milliseconds(5))
        client.shutdown()

        let outcome = await withTaskGroup(of: (count: Int, error: (any Error)?)?.self) { group in
            // cancelAll() does not end a wait on reader.value by itself; cancel the reader so a
            // read that shutdown() left blocked still lets the group return and the test fail.
            group.addTask { await withTaskCancellationHandler { await reader.value } onCancel: { reader.cancel() } }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return nil }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        let ended = try #require(outcome, "the lazy read did not end within 10 s of shutdown()")
        #expect(ended.count < 2000)
        #expect((ended.error as? KurrentError) == .connectionClosed, "ended with \(String(describing: ended.error))")
        #expect(client.selector.connections.shutdownHandlerCount == 0)
    }

    @Test("Cancelling one read leaves a concurrent read on the read connection intact")
    func cancellingLazyKeepsSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        let (firstElement, signal) = AsyncStream.makeStream(of: Void.self)
        let reader = Task {
            defer { signal.finish() }
            var count = 0
            for try await _ in stream.read() {
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
        // The reader opened the read connection; the reads below share it.
        let createdBefore = client.selector.connections.createdReadConnectionCount

        let before = try await stream.read().reduce(0) { n, _ in n + 1 }
        reader.cancel()
        await #expect(throws: CancellationError.self) { _ = try await reader.value }
        let after = try await stream.read().reduce(0) { n, _ in n + 1 }

        #expect(before == 300)
        #expect(after == 300)
        #expect(client.selector.connections.createdReadConnectionCount == createdBefore)
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
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
        defer { client.shutdown() }
        let name = "LazyRead-Deadline-\(UUID().uuidString)"
        try await appendEvents(count: 300, to: client.streams(specified: name))
        let timed = streams(client, name: name, timeout: .seconds(2))

        let iterator = timed.read().makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .seconds(4))   // the producer is suspended in send; the deadline expires
        var failure: (any Error)?
        do { while try await iterator.next() != nil {} } catch { failure = error }

        let error = try #require(failure)
        #expect(!(error is CancellationError))
        // Post-acceptance errors reach the iterator as KurrentError, like a buffered read's stream.
        #expect(error as? KurrentError == .deadlineExceeded)
    }

    @Test("A subscription whose deadline expires while its consumer is idle ends with the deadline error")
    func subscriptionDeadlineIsNotCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let name = "LazyRead-SubDeadline-\(UUID().uuidString)"
        try await appendEvents(count: 300, to: client.streams(specified: name))
        let timed = streams(client, name: name, timeout: .seconds(2))

        let subscription = try await timed.subscribe { $0.revision = .start }
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .seconds(4))
        var failure: (any Error)?
        do { while try await iterator.next() != nil {} } catch { failure = error }

        let error = try #require(failure)
        #expect(!(error is CancellationError))
        #expect(error as? KurrentError == .deadlineExceeded)
    }

    @Test("A caught-up subscription whose deadline expires while the consumer waits ends with the deadline error")
    func caughtUpSubscriptionDeadline() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let name = "LazyRead-CaughtUp-\(UUID().uuidString)"
        try await appendEvents(count: 1, to: client.streams(specified: name))
        let timed = streams(client, name: name, timeout: .seconds(2))

        let subscription = try await timed.subscribe { $0.revision = .start }
        var failure: (any Error)?
        do { for try await _ in subscription.events {} } catch { failure = error }

        let error = try #require(failure, "the loop ended cleanly instead of with the deadline error")
        #expect(error as? KurrentError == .deadlineExceeded)
    }

    @Test("150 concurrent lazy reads with a slow consumer do not delay an append on the main connection")
    func slowLazyReadsDoNotDelayAppend() async throws {
        // A 64 KiB HTTP/2 window and ~4 KB events: the server can send a read (~200 KB) only as its
        // consumer pulls, so the read holds its stream until all but the last window is consumed
        // (~34 events × 60 ms ≈ 2 s). With the default 8 MiB window every read would
        // end on the server at once and free its slot, and the test could not tell the connections apart.
        let client = KurrentDBClient(settings: settings.smallHTTP2Window())
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-Slow-\(UUID().uuidString)")
        let padding = String(repeating: "x", count: 4000)
        _ = try await stream.append(events: (0 ..< 50).map { _ in
            EventData(eventType: "LazyRead-Test", model: ["Description": padding])
        }) { $0.expectedRevision = .any }
        let target = client.streams(specified: "LazyRead-Append-\(UUID().uuidString)")

        // Every read that holds its stream has received its first element; above the server's
        // 100-stream limit per connection the rest wait for a slot. On the main connection the append
        // would wait behind them until the first reads free their streams (~2 s; measured 1.7 s with
        // 2 KB events); on the read connection it takes milliseconds.
        let started = StartedCount()
        let elapsed = try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 150 {
                group.addTask {
                    var first = true
                    for try await _ in stream.read() {
                        if first { first = false; started.increment() }
                        try await Task.sleep(for: .milliseconds(60))
                    }
                }
            }
            let readsHolding = try await eventually { started.value >= 100 }
            try #require(readsHolding, "fewer than 100 lazy reads started")
            let clock = ContinuousClock()
            let elapsed = try await clock.measure {
                _ = try await target.append(events: [event()]) { $0.expectedRevision = .any }
            }
            try await group.waitForAll()
            return elapsed
        }
        #expect(elapsed < .seconds(1), "the append took \(elapsed) behind 150 held lazy reads")
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }

    @Test("The 101st lazy read held open on one read connection gets deadlineExceeded within the budget, without a node reset")
    func readBeyondTheStreamLimitHitsTheBudget() async throws {
        // A 64 KiB HTTP/2 window and ~4 KB events (~200 KB per read): a read advanced once and then
        // left alone keeps its stream, since the server cannot send the rest until it is pulled.
        // 100 of them fill the read connection (KurrentDB's SETTINGS_MAX_CONCURRENT_STREAMS); the
        // 101st waits for a slot, and that wait is part of the budget.
        let client = KurrentDBClient(settings: settings.smallHTTP2Window().defaultDeadline(1_000))
        defer { client.shutdown() }
        let stream = client.streams(specified: "LazyRead-Held-\(UUID().uuidString)")
        let padding = String(repeating: "x", count: 4000)
        _ = try await stream.append(events: (0 ..< 50).map { _ in
            EventData(eventType: "LazyRead-Test", model: ["Description": padding])
        }) { $0.expectedRevision = .any }
        let node = try await client.selector.select()
        let expiry = await client.selector.selectedNodeExpiry   // a rediscovery would renew it

        var held: [Streams<SpecifiedStream>.ReadCall.Iterator] = []
        for _ in 0 ..< 100 {
            let iterator = stream.read().makeAsyncIterator()
            _ = try await iterator.next()
            held.append(iterator)
        }
        let connections = client.selector.connections
        #expect(connections.createdReadConnectionCount == 1)
        #expect(connections.readEntrySnapshot(for: node.endpoint)?.retainCount == 100)

        // Raced against 3 s, so a read the budget does not bound fails here instead of at the time limit.
        let start = ContinuousClock.now
        let blocked = Task { () -> (any Error)? in
            do {
                _ = try await stream.read().makeAsyncIterator().next()
                return nil
            } catch {
                return error
            }
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(3))
            blocked.cancel()
        }
        let error = await blocked.value
        watchdog.cancel()
        let elapsed = ContinuousClock.now - start

        #expect((error as? KurrentError) == .deadlineExceeded, "\(String(describing: error)) after \(elapsed)")
        #expect(elapsed <= .milliseconds(1_200), "\(elapsed)")
        #expect(connections.createdReadConnectionCount == 1)
        #expect(await client.selector.cachedNodeForTesting?.endpoint == node.endpoint)
        #expect(await client.selector.selectedNodeExpiry == expiry, "the node was invalidated and discovered again")

        held.removeAll()
        #expect(try await eventually { connections.readEntrySnapshot(for: node.endpoint)?.retainCount == 0 })
    }


    @Test("A lazy read inside a lazy read's loop body completes")
    func nestedLazyReadCompletes() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let outer = client.streams(specified: "LazyRead-Outer-\(UUID().uuidString)")
        let inner = client.streams(specified: "LazyRead-Inner-\(UUID().uuidString)")
        try await appendEvents(count: 5, to: outer)
        try await appendEvents(count: 5, to: inner)

        var outerCount = 0
        var innerCount = 0
        for try await _ in outer.read() {
            outerCount += 1
            for try await _ in inner.read() { innerCount += 1 }
        }
        #expect(outerCount == 5)
        #expect(innerCount == 25)
        #expect(try await eventually { (try? await readRetainCount(client)) == 0 })
    }
}

/// How many lazy reads have received their first element.
private final class StartedCount: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func increment() { count.withLock { $0 += 1 } }
}
