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

/// Accepts TCP connections and never writes, so an RPC on it waits for acceptance forever.
private struct SilentListener {
    let channel: any Channel
    var port: Int { channel.localAddress!.port! }

    static func start() async throws -> SilentListener {
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0)
            .get()
        return SilentListener(channel: channel)
    }

    func stop() async { try? await channel.close() }
}

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
        #expect(node.connections.createdSharedConnectionCount == 1)
        #expect(node.connections.createdDedicatedConnectionCount == 0)
        #expect(node.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("open: ReadAll takes the same path")
    func openReadAllRefused() async throws {
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }
        await #expect(throws: KurrentError.self) {
            _ = try await usecase.open(node: node, callOptions: boundedCallOptions, credentials: nil)
        }
        #expect(node.connections.createdSharedConnectionCount == 1)
        #expect(node.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
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
        #expect(node.connections.sharedEntrySnapshot(for: Endpoint(host: "127.0.0.1", port: port))?.retainCount == 0)
    }

    // MARK: ReadCall.lazy

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
            for try await _ in streams.read().lazy {}
        }
        #expect(selector.connections.createdSharedConnectionCount == 1)
        #expect(selector.connections.createdDedicatedConnectionCount == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("lazy: an iterator that is never advanced takes no lease")
    func droppedIteratorTakesNoLease() async throws {
        let selector = await makeSelector(supporting: [Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor])
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        do { _ = streams.read().lazy.makeAsyncIterator() }
        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused) == nil)
    }

    @Test("lazy: a caller that is already cancelled gets CancellationError before node discovery")
    func lazyPreCancelled() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let reader = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            for try await _ in streams.read().lazy {}
        }
        await #expect(throws: CancellationError.self) { try await reader.value }
        #expect(selector.connections.createdSharedConnectionCount == 0)
    }

    @Test("lazy: cancelling the caller during node discovery surfaces CancellationError")
    func lazyCancelDuringDiscovery() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let reader = Task { for try await _ in streams.read().lazy {} }
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

        let reader = Task { for try await _ in streams.read().lazy {} }
        try await Task.sleep(for: .milliseconds(300))
        reader.cancel()
        let outcome = await reader.result
        await listener.stop()

        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount == 0)
    }

    @Test("lazy: after the open fails once, next() returns nil and opens no second RPC")
    func lazyFinishedAfterOpenFailure() async throws {
        let selector = await makeSelector(supporting: [Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor])
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        var iterator = streams.read().lazy.makeAsyncIterator()
        await #expect(throws: KurrentError.self) { _ = try await iterator.next() }
        let second = try await iterator.next()
        #expect(second == nil)
        #expect(selector.connections.createdSharedConnectionCount == 1)
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

        // Specified-stream reads do not expect control frames, same as read() today.
        let specified = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        #expect(throws: (any Error).self) { _ = try specified.scopedResponse(for: checkpoint) }
    }
}
