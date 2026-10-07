//
//  DefaultDeadlinePathTests.swift
//  swift-kurrentdb
//
//  No server needed. Every call targets a SilentListener, which never answers, so a call ends
//  only through its deadline or its caller's cancellation. That makes "the default deadline is
//  applied" and "cancellation is reported as connectionClosed" independent of machine speed.
//

import GRPCCore
import Testing
@testable import KurrentDB

@Suite("Default deadline on completing calls", .serialized, .timeLimit(.minutes(1)))
struct DefaultDeadlinePathTests {
    private func makeNode(port: Int, defaultDeadline: Int, supporting descriptors: [GRPCCore.MethodDescriptor]) -> Node {
        let settings = ClientSettings.localhost().defaultDeadline(defaultDeadline)
        let info = ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        return Node(endpoint: Endpoint(host: "127.0.0.1", port: UInt32(port)), settings: settings, serverInfo: info, connections: provider)
    }

    private func isDeadlineExceeded(_ error: any Error) -> Bool {
        if case .deadlineExceeded = error as? KurrentError { return true }
        return false
    }

    @Test("A unary call ends with deadlineExceeded at the default deadline")
    func unary() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Delete(to: .init(name: "any"), options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("A client-streaming append ends with deadlineExceeded at the default deadline")
    func clientStreaming() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Append(to: .init(name: "any"), events: [EventData(eventType: "T", model: ["k": "v"])], options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("A buffered read ends with deadlineExceeded at the default deadline")
    func bufferedRead() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("A batch append ends with deadlineExceeded at the default deadline")
    func batchAppend() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let record = try EventRecord(eventType: "T", payload: .json(["k": "v"]))
        let usecase = Streams<MultiStreamsTarget>.BatchAppend(streamEvents: [StreamEvent(stream: "any", records: [record])])
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("An explicit CallOptions.timeout wins over the default deadline")
    func explicitTimeoutWins() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Delete(to: .init(name: "any"), options: .init())
        // The default deadline alone would let this call wait an hour.
        let node = makeNode(port: listener.port, defaultDeadline: 3_600_000, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }
        var options = CallOptions.defaults
        options.timeout = .milliseconds(300)

        await #expect { _ = try await usecase.perform(node: node, callOptions: options) } throws: { isDeadlineExceeded($0) }
    }

    @Test("Cancelling the caller of a buffered read reports connectionClosed, not an internal error")
    func bufferedReadCallerCancellation() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: .max, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        let reader = Task { try await usecase.perform(node: node, callOptions: .defaults) }
        try await Task.sleep(for: .milliseconds(300))
        reader.cancel()
        let outcome = await reader.result
        #expect { _ = try outcome.get() } throws: { error in
            if case .connectionClosed = error as? KurrentError { return true }
            return false
        }
    }
}
