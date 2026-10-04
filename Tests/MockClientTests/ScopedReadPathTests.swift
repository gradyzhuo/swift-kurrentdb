//
//  ScopedReadPathTests.swift
//  swift-kurrentdb
//
//  No server needed: everything points at 127.0.0.1:1 (ECONNREFUSED). Verifies that the scoped
//  path uses the shared connection, fails before calling body, and returns the lease.
//

import GRPCCore
import NIOCore
import NIOPosix
import Synchronization
import Testing
@testable import KurrentDB

/// Counts body invocations; a class so closures can capture it.
private final class CallCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func hit() { count.withLock { $0 += 1 } }
}

/// A TCP listener that accepts connections but never speaks HTTP/2, so a call on it waits for
/// the connection indefinitely.
private struct SilentListener: Sendable {
    let channel: any Channel
    let port: Int

    static func start() async throws -> SilentListener {
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0)
            .get()
        guard let port = channel.localAddress?.port else {
            try await channel.close()
            throw KurrentError.internalClientError(reason: "listener has no bound port")
        }
        return SilentListener(channel: channel, port: port)
    }

    func stop() async {
        try? await channel.close()
    }
}

@Suite("Scoped read path", .serialized, .timeLimit(.minutes(1)))
struct ScopedReadPathTests {
    private static let refused = Endpoint(host: "127.0.0.1", port: 1)

    private func makeInfo(supporting descriptors: [GRPCCore.MethodDescriptor]) -> ServerFeatures.ServiceInfo {
        ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
    }

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

    private var boundedCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(2)
        return options
    }

    @Test("Read: a refused connection throws KurrentError before body runs, on the shared path, lease returned")
    func readFailsBeforeBody() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let selector = await makeSelector(supporting: [usecase.methodDescriptor])
        defer { selector.connections.shutdown() }
        let bodyCalls = CallCounter()

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.performScoped(selector: selector, callOptions: boundedCallOptions) { _ in
                bodyCalls.hit()
            }
        }

        #expect(bodyCalls.value == 0)
        #expect(selector.connections.createdSharedConnectionCount == 1)
        #expect(selector.connections.createdDedicatedConnectionCount == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("ReadAll: same guarantees")
    func readAllFailsBeforeBody() async throws {
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: .init())
        let selector = await makeSelector(supporting: [usecase.methodDescriptor])
        defer { selector.connections.shutdown() }
        let bodyCalls = CallCounter()

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.performScoped(selector: selector, callOptions: boundedCallOptions) { _ in
                bodyCalls.hit()
            }
        }

        #expect(bodyCalls.value == 0)
        #expect(selector.connections.createdSharedConnectionCount == 1)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("Unsupported method throws unsupportedFeature without acquiring a lease")
    func unsupportedFeature() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let selector = await makeSelector(supporting: [])
        defer { selector.connections.shutdown() }

        do {
            _ = try await usecase.performScoped(selector: selector, callOptions: boundedCallOptions) { _ in }
            Issue.record("expected unsupportedFeature")
        } catch {
            guard case .unsupportedFeature = error as? KurrentError else {
                Issue.record("expected unsupportedFeature, got \(error)")
                return
            }
        }
        #expect(selector.connections.createdSharedConnectionCount == 0)
    }

    @Test("Cancelling the caller while waiting for acceptance ends the call and returns the lease")
    func cancelDuringAcceptance() async throws {
        let listener = try await SilentListener.start()
        let endpoint = Endpoint(host: "127.0.0.1", port: UInt32(listener.port))
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        let settings = ClientSettings(clusterMode: .standalone(endpoint: endpoint)).operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        let node = Node(endpoint: endpoint, settings: settings, serverInfo: makeInfo(supporting: [usecase.methodDescriptor]), connections: selector.connections)
        await selector.cacheNodeForTesting(node)
        defer { selector.connections.shutdown() }
        let bodyCalls = CallCounter()

        // No timeout and a server that never answers: only the cancellation can end this call.
        let task = Task {
            try await usecase.performScoped(selector: selector, callOptions: .defaults) { _ in
                bodyCalls.hit()
            }
        }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        let outcome = await task.result
        await listener.stop()

        guard case let .failure(error) = outcome else {
            Issue.record("expected a failure")
            return
        }
        #expect(error as? KurrentError == .connectionClosed)
        #expect(bodyCalls.value == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount == 0)
    }
}
