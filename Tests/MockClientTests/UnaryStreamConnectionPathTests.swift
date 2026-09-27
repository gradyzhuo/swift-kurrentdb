//
//  UnaryStreamConnectionPathTests.swift
//  swift-kurrentdb
//
//  No server needed: everything points at 127.0.0.1:1 (ECONNREFUSED), so every RPC fails.
//  What is verified is not the result but which connection perform used: the shared path
//  bumps createdSharedConnectionCount to 1 and the dedicated path bumps
//  createdDedicatedConnectionCount. Those monotonic counters are the only assertions that
//  tell the two paths apart — activeDedicatedConnectionCount is 0 after failure on both.
//

import GRPCCore
import Testing
@testable import KurrentDB

@Suite("UnaryStream connection path", .serialized, .timeLimit(.minutes(1)))
struct UnaryStreamConnectionPathTests {
    private static let refused = Endpoint(host: "127.0.0.1", port: 1)

    private func makeInfo(supporting descriptors: [GRPCCore.MethodDescriptor]) -> ServerFeatures.ServiceInfo {
        ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
    }

    private func makeNode(supporting descriptors: [GRPCCore.MethodDescriptor]) -> Node {
        let settings = ClientSettings.localhost()
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        return Node(endpoint: Self.refused, settings: settings, serverInfo: makeInfo(supporting: descriptors), connections: provider)
    }

    /// For `perform(selector:)`: both the seed and the cached node point at the refused port and
    /// retries are off, so a failure never invalidates the cache and probes anything via discovery.
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

    @Test("Read 走共用連線")
    func readTakesSharedPath() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.perform(node: node, callOptions: boundedCallOptions)
        }

        #expect(node.connections.createdSharedConnectionCount == 1)
        #expect(node.connections.createdDedicatedConnectionCount == 0)
        #expect(node.connections.activeDedicatedConnectionCount == 0)
        #expect(node.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("ReadAll 走共用連線")
    func readAllTakesSharedPath() async throws {
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.perform(node: node, callOptions: boundedCallOptions)
        }

        #expect(node.connections.createdSharedConnectionCount == 1)
        #expect(node.connections.createdDedicatedConnectionCount == 0)
        #expect(node.connections.activeDedicatedConnectionCount == 0)
    }

    @Test("Subscribe 仍走獨立連線")
    func subscribeTakesDedicatedPath() async throws {
        let usecase = Streams<SpecifiedStream>.Subscribe(from: .init(name: "any"), options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.perform(node: node, callOptions: boundedCallOptions)
        }

        #expect(node.connections.createdSharedConnectionCount == 0)
        #expect(node.connections.createdDedicatedConnectionCount == 1)
    }

    // MARK: - Through perform(selector:) — the path the public facades take

    /// The base extension's perform(selector:) binds perform(node:) statically to the
    /// dedicated-connection version, so the constrained extension must provide its own
    /// perform(selector:). The perform(node:) tests above cannot guard that: remove the
    /// constrained perform(selector:) and they still pass, while these fall back to dedicated.
    @Test("Read 經 perform(selector:) 走共用連線")
    func readTakesSharedPathThroughSelector() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let selector = await makeSelector(supporting: [usecase.methodDescriptor])
        defer { selector.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.perform(selector: selector, callOptions: boundedCallOptions)
        }

        #expect(selector.connections.createdSharedConnectionCount == 1)
        #expect(selector.connections.createdDedicatedConnectionCount == 0)
    }

    @Test("Subscribe 經 perform(selector:) 仍走獨立連線")
    func subscribeTakesDedicatedPathThroughSelector() async throws {
        let usecase = Streams<SpecifiedStream>.Subscribe(from: .init(name: "any"), options: .init())
        let selector = await makeSelector(supporting: [usecase.methodDescriptor])
        defer { selector.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.perform(selector: selector, callOptions: boundedCallOptions)
        }

        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.createdDedicatedConnectionCount == 1)
    }
}
