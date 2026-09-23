//
//  ServerFeatures.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public final class ServerFeatures: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_ServerFeatures_ServerFeatures.Client<HTTP2ClientTransport.Posix>

    internal let endpoint: Endpoint
    internal let settings: ClientSettings
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup
    /// 查詢支援的方法是單一回應的 RPC,走 client 的共用連線。
    internal let connections: ConnectionProvider

    init(endpoint: Endpoint, settings: ClientSettings, connections: ConnectionProvider, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.endpoint = endpoint
        self.settings = settings
        self.connections = connections
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension ServerFeatures {
    public func getSupportedMethods() async throws(KurrentError) -> ServiceInfo {
        let usecase = GetSupportedMethods()
        let lease = try connections.acquire(endpoint)
        defer { lease.release() }
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = try Metadata(from: settings)
            return try await usecase.send(connection: lease.client, request: usecase.request(metadata: metadata), callOptions: callOptions)
        }
    }
}
