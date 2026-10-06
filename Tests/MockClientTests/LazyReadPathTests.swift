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
}
