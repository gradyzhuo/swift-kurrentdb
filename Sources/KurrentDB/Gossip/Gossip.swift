//
//  Gossip.swift
//  KurrentGossip
//
//  Created by Grady Zhuo on 2023/10/17.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

/// Performs gossip protocol requests against a single Kurrent cluster endpoint.
public final class Gossip: Sendable {
    package typealias UnderlyingClient = EventStore_Client_Gossip_Gossip.Client<HTTP2ClientTransport.Posix>

    internal let endpoint: Endpoint
    internal let settings: ClientSettings
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup
    /// gossip 讀取是單一回應的 RPC,走 client 的共用連線。
    internal let connections: ConnectionProvider

    init(endpoint: Endpoint, settings: ClientSettings, connections: ConnectionProvider, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.endpoint = endpoint
        self.settings = settings
        self.connections = connections
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Gossip {
    /// Reads the current member list from this endpoint's gossip API.
    ///
    /// Members whose state appears in `notAllowedStates` are excluded from the result.
    /// The returned array is sorted by node preference priority as defined in `ClientSettings`.
    ///
    /// - Parameter notAllowedStates: Node states excluded from the result.
    /// - Returns: An array of ``MemberInfo`` sorted by preference priority, excluding any disallowed states.
    /// - Throws: `KurrentError` if the gRPC call fails or the response cannot be decoded.
    public func read(timeout _: Duration, notAllowedStates: [Gossip.VNodeState] = []) async throws(KurrentError) -> [MemberInfo] {
        let usecase = Read()
        let lease = try connections.acquire(endpoint)
        defer { lease.release() }
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = try Metadata(from: settings)
            let memberInfos = try await usecase.send(connection: lease.client, metadata: metadata, callOptions: callOptions)
            return memberInfos
                .filter { !notAllowedStates.contains($0.state) }
                .sorted { settings.nodePreference.priority(state: $0.state) < settings.nodePreference.priority(state: $1.state)
            }
        }
    }
}
