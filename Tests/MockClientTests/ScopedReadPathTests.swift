//
//  ScopedReadPathTests.swift
//  swift-kurrentdb
//
//  No server needed: everything points at 127.0.0.1:1 (ECONNREFUSED). Verifies that the scoped
//  path uses the shared connection, fails before calling body, and returns the lease.
//

import Foundation
import GRPCCore
import Synchronization
import Testing
@testable import KurrentDB

/// Counts body invocations; a class so closures can capture it.
private final class CallCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func hit() { count.withLock { $0 += 1 } }
}

/// A TCP listener that completes handshakes (kernel backlog) but never speaks HTTP/2, so a call
/// on it waits for the connection indefinitely.
private final class SilentListener: Sendable {
    let fd: Int32
    let port: Int

    init() {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        address.sin_port = 0
        withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        listen(fd, 16)
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &length) }
        }
        self.fd = fd
        port = Int(UInt16(bigEndian: bound.sin_port))
    }

    deinit { close(fd) }
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
        let listener = SilentListener()
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

        guard case let .failure(error) = outcome else {
            Issue.record("expected a failure")
            return
        }
        #expect(error as? KurrentError == .connectionClosed)
        #expect(bodyCalls.value == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount == 0)
        withExtendedLifetime(listener) {}
    }
}
