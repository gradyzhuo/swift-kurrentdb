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

    private func makeNode(supporting descriptors: [GRPCCore.MethodDescriptor]) -> Node {
        let settings = ClientSettings.localhost()
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        let info = ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
        return Node(endpoint: Self.refused, settings: settings, serverInfo: info, connections: provider)
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
    }
}
