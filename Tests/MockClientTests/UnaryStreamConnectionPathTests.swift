//
//  UnaryStreamConnectionPathTests.swift
//  swift-kurrentdb
//
//  不需要伺服器:指向 127.0.0.1:1(ECONNREFUSED),RPC 一定失敗。要驗證的不是結果,
//  而是 perform(node:) 走了哪一條連線:共用連線會讓 createdSharedConnectionCount 變 1,
//  獨立連線不會動它。這是唯一能區分兩條路徑的斷言 —— activeDedicatedConnectionCount
//  在失敗後兩條路徑都是 0。
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

    /// 給 `perform(selector:)` 用:seed 與快取的 node 都指向 refused port,retry 關掉,
    /// 所以失敗後不會 invalidate → discovery 去探測任何地方。
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

    /// base extension 的 perform(selector:) 會把 perform(node:) 靜態綁到獨立連線那一版,
    /// 所以 constrained extension 必須自己提供 perform(selector:)。上面直接呼叫 perform(node:)
    /// 的測試守不住這件事 —— 把 constrained 的 perform(selector:) 拿掉,它們照樣過,但這裡會退回獨立連線。
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
