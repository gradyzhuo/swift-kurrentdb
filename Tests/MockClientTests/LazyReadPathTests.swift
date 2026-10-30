//
//  LazyReadPathTests.swift
//  swift-kurrentdb
//
//  No server needed. Most tests point at 127.0.0.1:1 (ECONNREFUSED); the acceptance-cancel test
//  uses a local NIO listener that accepts TCP but never speaks HTTP/2, so the call really waits.
//  What is verified is which connection path was used and that every lease is returned.
//

import GRPCCore
import NIOCore
import NIOPosix
import Synchronization
import Testing
@testable import KurrentDB

@Suite("Lazy read path", .serialized, .timeLimit(.minutes(1)))
struct LazyReadPathTests {
    private static let refused = Endpoint(host: "127.0.0.1", port: 1)

    private func makeInfo(supporting descriptors: [GRPCCore.MethodDescriptor]) -> ServerFeatures.ServiceInfo {
        ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
    }

    private func makeNode(endpoint: Endpoint = refused, supporting descriptors: [GRPCCore.MethodDescriptor]) -> Node {
        let settings = ClientSettings.localhost()
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        return Node(endpoint: endpoint, settings: settings, serverInfo: makeInfo(supporting: descriptors), connections: provider)
    }

    private var boundedCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(2)
        return options
    }

    // MARK: open(node:)

    @Test("open: a refused connection throws KurrentError on the shared path and returns the lease")
    func openRefusedReturnsLease() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.open(node: node, callOptions: boundedCallOptions, credentials: nil)
        }
        #expect(node.connections.createdReadConnectionCount == 1)
        #expect(node.connections.createdSharedConnectionCount == 0)
        #expect(node.connections.createdDedicatedConnectionCount == 0)
        #expect(node.connections.readEntrySnapshot(for: Self.refused)?.retainCount == 0)
        #expect(node.connections.shutdownHandlerCount == 0)   // removed in open()'s failure branch
    }

    @Test("open: ReadAll takes the same path")
    func openReadAllRefused() async throws {
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }
        await #expect(throws: KurrentError.self) {
            _ = try await usecase.open(node: node, callOptions: boundedCallOptions, credentials: nil)
        }
        #expect(node.connections.createdReadConnectionCount == 1)
        #expect(node.connections.createdSharedConnectionCount == 0)
        #expect(node.connections.readEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("open: unsupported method throws unsupportedFeature without acquiring a lease")
    func openUnsupported() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(supporting: [])
        defer { node.connections.shutdown() }
        await #expect {
            _ = try await usecase.open(node: node, callOptions: boundedCallOptions, credentials: nil)
        } throws: { error in
            if case .unsupportedFeature = error as? KurrentError { return true }
            return false
        }
        #expect(node.connections.createdSharedConnectionCount == 0)
        #expect(node.connections.createdReadConnectionCount == 0)
    }

    @Test("open: cancelling the caller while waiting for acceptance ends the call and returns the lease")
    func openCancelDuringAcceptance() async throws {
        let listener = try await SilentListener.start()
        let port = UInt32(listener.port)   // a closed channel has no local address
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(endpoint: Endpoint(host: "127.0.0.1", port: port), supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        let opener = Task {
            try await usecase.open(node: node, callOptions: .defaults, credentials: nil)   // no timeout: waits
        }
        try await Task.sleep(for: .milliseconds(300))
        opener.cancel()
        let outcome = await opener.result
        await listener.stop()

        #expect {
            _ = try outcome.get()
        } throws: { error in
            if case .connectionClosed = error as? KurrentError { return true }
            return false
        }
        #expect(node.connections.readEntrySnapshot(for: Endpoint(host: "127.0.0.1", port: port))?.retainCount == 0)
    }

    // MARK: ReadCall iteration

    /// Seed and cached node both point at the refused port; retries are off.
    private func makeSelector(supporting descriptors: [GRPCCore.MethodDescriptor]) async -> NodeSelector {
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        let settings = ClientSettings(clusterMode: .standalone(endpoint: Self.refused)).operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        let node = Node(endpoint: Self.refused, settings: settings, serverInfo: makeInfo(supporting: descriptors), connections: selector.connections)
        await selector.cacheNodeForTesting(node)
        return selector
    }

    /// No cached node: the first call goes through node discovery.
    private func makeUncachedSelector() -> NodeSelector {
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        return NodeSelector(settings: ClientSettings(clusterMode: .standalone(endpoint: Self.refused)).operationRetryPolicy(policy))
    }

    private func makeStreams(_ selector: NodeSelector) -> Streams<SpecifiedStream> {
        Streams(target: .specified("any"), selector: selector, callOptions: boundedCallOptions)
    }

    @Test("lazy: a refused connection throws KurrentError at the first next(), shared path, lease returned")
    func lazyRefused() async throws {
        let selector = await makeSelector(supporting: [Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor])
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        await #expect(throws: KurrentError.self) {
            for try await _ in streams.read() {}
        }
        #expect(selector.connections.createdReadConnectionCount == 1)
        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.createdDedicatedConnectionCount == 0)
        #expect(selector.connections.readEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("lazy: an iterator that is never advanced takes no lease")
    func droppedIteratorTakesNoLease() async throws {
        let selector = await makeSelector(supporting: [Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor])
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        do { _ = streams.read().makeAsyncIterator() }
        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.createdReadConnectionCount == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused) == nil)
        #expect(selector.connections.readEntrySnapshot(for: Self.refused) == nil)
    }

    @Test("lazy: a caller that is already cancelled gets CancellationError before node discovery")
    func lazyPreCancelled() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let reader = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            for try await _ in streams.read() {}
        }
        await #expect(throws: CancellationError.self) { try await reader.value }
        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.createdReadConnectionCount == 0)
    }

    @Test("lazy: cancelling the caller during node discovery surfaces CancellationError")
    func lazyCancelDuringDiscovery() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let reader = Task { for try await _ in streams.read() {} }
        try await Task.sleep(for: .milliseconds(200))   // discovery against the refused port retries for ~1s
        reader.cancel()
        await #expect(throws: CancellationError.self) { try await reader.value }
    }

    @Test("lazy: cancelling the caller while waiting for acceptance surfaces CancellationError and returns the lease")
    func lazyCancelDuringAcceptance() async throws {
        let listener = try await SilentListener.start()
        let endpoint = Endpoint(host: "127.0.0.1", port: UInt32(listener.port))
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        let settings = ClientSettings(clusterMode: .standalone(endpoint: endpoint)).operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        defer { selector.connections.shutdown() }
        let descriptor = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor
        await selector.cacheNodeForTesting(Node(endpoint: endpoint, settings: settings, serverInfo: makeInfo(supporting: [descriptor]), connections: selector.connections))
        let streams = Streams<SpecifiedStream>(target: .specified("any"), selector: selector, callOptions: .defaults)

        let reader = Task { for try await _ in streams.read() {} }
        try await Task.sleep(for: .milliseconds(300))
        reader.cancel()
        let outcome = await reader.result
        await listener.stop()

        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(selector.connections.readEntrySnapshot(for: endpoint)?.retainCount == 0)
    }

    @Test("lazy: a pre-cancelled first next() finishes the iterator; a later next() opens nothing")
    func lazyPreCancelledFirstNextFinishes() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let iterator = streams.read().makeAsyncIterator()
        let reader = Task { () -> (firstThrewCancellation: Bool, second: Streams<SpecifiedStream>.ReadResponse?) in
            withUnsafeCurrentTask { $0?.cancel() }
            var firstThrewCancellation = false
            do {
                _ = try await iterator.next()
            } catch is CancellationError {
                firstThrewCancellation = true
            }
            return (firstThrewCancellation, try await iterator.next())   // finished: nil, no RPC
        }
        let outcome = try await reader.value
        #expect(outcome.firstThrewCancellation)
        #expect(outcome.second == nil)
        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.createdReadConnectionCount == 0)
    }

    @Test("lazy: after the open fails once, next() returns nil and opens no second RPC")
    func lazyFinishedAfterOpenFailure() async throws {
        let selector = await makeSelector(supporting: [Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor])
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let iterator = streams.read().makeAsyncIterator()
        await #expect(throws: KurrentError.self) { _ = try await iterator.next() }
        let second = try await iterator.next()
        #expect(second == nil)
        #expect(selector.connections.createdReadConnectionCount == 1)
        #expect(selector.connections.createdSharedConnectionCount == 0)
    }

    // MARK: errors after acceptance (S15)

    @Test("A call deadline expiring mid-stream ends a lazy read with KurrentError.deadlineExceeded")
    func lazyDeadlineMidStreamIsKurrentError() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        var options = CallOptions.defaults
        options.timeout = .milliseconds(300)
        let client = KurrentDBClient(settings: fake.settings, defaultCallOptions: options)
        defer { try? client.shutdown() }
        var count = 0
        await #expect(throws: KurrentError.deadlineExceeded) {
            for try await _ in client.streams(specified: "orders").read() { count += 1 }
        }
        #expect(count == 3)
        #expect(fake.readsStarted == 1)
    }

    @Test("A server error after two events reaches a lazy read as KurrentError.serverError")
    func lazyServerErrorMidStreamIsKurrentError() async throws {
        let fake = InProcessKurrentDB(read: .events(2, then: .error(RPCError(code: .internalError, message: "boom"))))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        var count = 0
        await #expect(throws: KurrentError.serverError("boom")) {
            for try await _ in client.streams(specified: "orders").read() { count += 1 }
        }
        #expect(count == 2)
    }

    @Test("A call deadline expiring mid-stream ends a buffered read with KurrentError.deadlineExceeded")
    func bufferedDeadlineMidStreamIsKurrentError() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        var options = CallOptions.defaults
        options.timeout = .milliseconds(300)
        let client = KurrentDBClient(settings: fake.settings, defaultCallOptions: options)
        defer { try? client.shutdown() }
        await #expect(throws: KurrentError.deadlineExceeded) {
            for try await _ in try await client.streams(specified: "orders").read().buffered {}
        }
    }

    @Test("A server error after two events reaches a buffered read as KurrentError.serverError")
    func bufferedServerErrorMidStreamIsKurrentError() async throws {
        let fake = InProcessKurrentDB(read: .events(2, then: .error(RPCError(code: .internalError, message: "boom"))))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        var count = 0
        await #expect(throws: KurrentError.serverError("boom")) {
            for try await _ in try await client.streams(specified: "orders").read().buffered { count += 1 }
        }
        #expect(count == 2)
    }

    // MARK: read connection (§5.1.5)

    @Test("A lazy read holding the only stream slot of its connection does not block a unary call on the main connection")
    func heldLazyReadLeavesMainConnectionFree() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold), maxConcurrentStreams: 1)
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let held = client.streams(specified: "orders").read().makeAsyncIterator()
        _ = try await held.next()

        // Gossip runs on the main connection; on the read connection it would wait for the held slot.
        let members = try await client.readCluster(timeout: .seconds(1))
        #expect(!members.isEmpty)
        #expect(client.selector.connections.createdReadConnectionCount == 1)
        #expect(client.selector.connections.createdSharedConnectionCount == 1)
        #expect(client.selector.connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 1)
        #expect(fake.openStreams == 1)   // the held read; gossip and discovery have ended
        withExtendedLifetime(held) {}
    }

    // MARK: shutdown (§5.1.6, S14)

    /// Waits until the condition holds or the timeout passes: after `break` the lease and the close
    /// handler are given back from the iterator's `deinit`, in the background.
    private func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    @Test("shutdown() during iteration ends the lazy read with exactly connectionClosed and empties the registry")
    func shutdownDuringIteration() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let connections = client.selector.connections
        let iterator = client.streams(specified: "orders").read().makeAsyncIterator()
        for _ in 0 ..< 3 { #expect(try await iterator.next() != nil) }
        #expect(connections.shutdownHandlerCount == 1)

        let shutter = Task {
            try await Task.sleep(for: .milliseconds(100))   // the consumer is suspended in next() by then
            connections.shutdown()
        }
        await #expect(throws: KurrentError.connectionClosed) { _ = try await iterator.next() }
        try await shutter.value
        #expect(try await iterator.next() == nil)
        #expect(connections.shutdownHandlerCount == 0)
    }

    @Test("shutdown() while waiting for acceptance ends the open with exactly connectionClosed")
    func shutdownDuringAcceptance() async throws {
        let listener = try await SilentListener.start()
        let endpoint = Endpoint(host: "127.0.0.1", port: UInt32(listener.port))
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        let settings = ClientSettings(clusterMode: .standalone(endpoint: endpoint)).operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        defer { selector.connections.shutdown() }
        let descriptor = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor
        await selector.cacheNodeForTesting(Node(endpoint: endpoint, settings: settings, serverInfo: makeInfo(supporting: [descriptor]), connections: selector.connections))
        let streams = Streams<SpecifiedStream>(target: .specified("any"), selector: selector, callOptions: .defaults)

        let reader = Task { for try await _ in streams.read() {} }
        try await Task.sleep(for: .milliseconds(300))
        #expect(selector.connections.shutdownHandlerCount == 1)   // registered before accepted.wait()
        selector.connections.shutdown()
        let outcome = await reader.result
        await listener.stop()

        #expect(throws: KurrentError.connectionClosed) { try outcome.get() }
        #expect(selector.connections.shutdownHandlerCount == 0)
    }

    @Test("shutdown() during node discovery ends the read with connectionClosed, not serverError (S14)")
    func shutdownDuringDiscovery() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let reader = Task { for try await _ in streams.read() {} }
        try await Task.sleep(for: .milliseconds(100))   // discovery against the refused port retries for ~1 s
        let shutdownAt = ContinuousClock.now
        selector.connections.shutdown()
        let outcome = await reader.result
        let elapsed = ContinuousClock.now - shutdownAt

        #expect(throws: KurrentError.connectionClosed) { try outcome.get() }
        // At once: within one discovery interval (100 ms), not after the remaining attempts.
        #expect(elapsed < .milliseconds(500), "ended \(elapsed) after shutdown()")
        #expect(selector.connections.createdReadConnectionCount == 0)
    }

    @Test("shutdown() called from inside the loop body ends the read at the next element without deadlocking", .timeLimit(.minutes(1)))
    func shutdownFromInsideTheLoopBody() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let connections = client.selector.connections
        var count = 0
        await #expect(throws: KurrentError.connectionClosed) {
            for try await _ in client.streams(specified: "orders").read() {
                count += 1
                if count == 2 { connections.shutdown() }
            }
        }
        #expect(count == 2)   // the third event, already offered by the producer, is not delivered
        #expect(connections.shutdownHandlerCount == 0)
    }

    @Test("A completed read and a broken read both leave the registry empty")
    func finishedReadsLeaveRegistryEmpty() async throws {
        let fake = InProcessKurrentDB(read: .events(3))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let connections = client.selector.connections

        var count = 0
        for try await _ in client.streams(specified: "orders").read() {
            count += 1
            #expect(connections.shutdownHandlerCount == 1)
        }
        #expect(count == 3)
        #expect(connections.shutdownHandlerCount == 0)   // close() is awaited on the way out

        for try await _ in client.streams(specified: "orders").read() {
            #expect(connections.shutdownHandlerCount == 1)
            break
        }
        #expect(try await eventually { connections.shutdownHandlerCount == 0 })
        #expect(try await eventually { connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0 })
        #expect(try await eventually { fake.openStreams == 0 })
    }

    // MARK: next(isolation:)

    @Test("A stored iterator is advanced from an actor with next(isolation:)")
    func storedIteratorAdvancedFromActor() async throws {
        let fake = InProcessKurrentDB(read: .events(2))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let cursor = Cursor(client.streams(specified: "orders").read())
        #expect(try await cursor.next() == 0)
        #expect(try await cursor.next() == 1)
        #expect(try await cursor.next() == nil)
    }

    // MARK: ReadCall is the sequence (§5.1.1)

    @Test("read() is a sequence: stored, iterated twice, each iteration its own RPC; first(where:) and reduce stop the RPC when done")
    func readCallIsASequence() async throws {
        let fake = InProcessKurrentDB(read: .events(5))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let call = client.streams(specified: "orders").read()
        let first = try await call.reduce(0) { n, _ in n + 1 }
        let second = try await call.reduce(0) { n, _ in n + 1 }
        #expect(first == 5 && second == 5)
        #expect(fake.readsStarted == 2)
        #expect(try await call.first { try $0.event.record.revision == 1 }?.event.record.revision == 1)
        #expect(fake.readsStarted == 3)
        #expect(try await eventually { client.selector.connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0 })
    }

    @available(*, deprecated)
    @Test("The deprecated .lazy is the same sequence")
    func lazyIsDeprecatedNoOp() async throws {
        let fake = InProcessKurrentDB(read: .events(2))
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        var count = 0
        for try await _ in client.streams(specified: "orders").read().lazy { count += 1 }
        #expect(count == 2)
        let lazy: Streams<SpecifiedStream>.ReadCall.Lazy = client.streams(specified: "orders").read().lazy
        #expect(try await lazy.reduce(0) { n, _ in n + 1 } == 2)
        #expect(fake.readsStarted == 2)
    }
}

@Suite("Lazy read control frames")
struct LazyReadControlFrameTests {
    @Test("ReadAll's scoped path skips control frames like its buffered path")
    func readAllScopedSkipsControlFrames() throws {
        let all = Streams<AllStreamsTarget>.ReadAll(options: .init())
        var checkpoint = Streams<AllStreamsTarget>.ReadAll.UnderlyingResponse()
        checkpoint.content = .checkpoint(.init())
        #expect(try all.scopedResponse(for: checkpoint) == nil)

        var notFound = Streams<AllStreamsTarget>.ReadAll.UnderlyingResponse()
        notFound.content = .streamNotFound(.init())
        // Not skipped: handle(message:) maps it to a resource-not-found error, as the buffered path does.
        #expect(throws: KurrentError.self) { _ = try all.scopedResponse(for: notFound) }

        // Specified-stream reads skip the same frames (S12): a compatibility ≥ 1 read sends position frames.
        let specified = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        #expect(try specified.scopedResponse(for: checkpoint) == nil)
    }

    @Test("Read's scoped path skips position frames instead of ending the read")
    func readScopedSkipsPositionFrames() throws {
        let read = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        var frame = Streams<SpecifiedStream>.Read.UnderlyingResponse()
        frame.content = .lastStreamPosition(41)
        #expect(try read.scopedResponse(for: frame) == nil)
    }

    @Test("Read's buffered path skips position frames: a compatibility ≥ 1 read yields the events alone")
    func readBufferedSkipsPositionFrames() async throws {
        var script = InProcessKurrentDB.ReadScript.events(2)
        var frame = Streams<SpecifiedStream>.Read.UnderlyingResponse()
        frame.content = .lastStreamPosition(1)
        script.messages.insert(frame, at: 0)
        let fake = InProcessKurrentDB(read: script)
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let count = try await client.streams(specified: "orders").read { $0.compatibility = 1 }.buffered.reduce(0) { n, _ in n + 1 }
        #expect(count == 2)
    }
}

/// Holds a lazy read's iterator in actor state and advances it from the actor, the shape
/// `next(isolation:)` exists for: without it the iterator would have to leave the actor's region.
private actor Cursor {
    private let iterator: Streams<SpecifiedStream>.ReadCall.Iterator
    init(_ call: Streams<SpecifiedStream>.ReadCall) { iterator = call.makeAsyncIterator() }
    func next() async throws -> UInt64? { try await iterator.next(isolation: self)?.event.record.revision }
}
