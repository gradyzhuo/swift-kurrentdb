//
//  SilentListener.swift
//  swift-kurrentdb
//

import NIOCore
import NIOPosix

/// Accepts TCP connections and never writes, so an RPC on it waits forever — until its deadline,
/// or until the caller cancels. Makes timing-dependent paths deterministic without a server.
struct SilentListener {
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
