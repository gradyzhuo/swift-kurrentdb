//
//  Connection.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/23.
//
import GRPCCore
import GRPCNIOTransportHTTP2
import NIO

public struct Node: Sendable {
    package let endpoint: Endpoint
    package let settings: ClientSettings
    package let serverInfo: ServerFeatures.ServiceInfo
    /// Where the client this node belongs to gets its connections. `perform(node:)` takes a shared or a
    /// dedicated connection from it, so the provider is not threaded through every facade and `perform`.
    ///
    /// Note: holding a `Node` keeps the whole provider, and its cache of shared connections, alive.
    package let connections: ConnectionProvider

    init(endpoint: Endpoint, settings: ClientSettings, serverInfo: ServerFeatures.ServiceInfo, connections: ConnectionProvider) {
        self.endpoint = endpoint
        self.settings = settings
        self.serverInfo = serverInfo
        self.connections = connections
    }
    
    
}
