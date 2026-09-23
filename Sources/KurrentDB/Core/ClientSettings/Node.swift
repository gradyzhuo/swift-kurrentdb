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
    /// 這個 node 所屬 client 的連線來源。`perform(node:)` 由此取得共用或獨立連線,
    /// 因此不需要把 provider 另外穿過每個 facade 與 perform 的簽章。
    ///
    /// 注意:持有一個 `Node` 會讓整個 provider(及其共用連線快取)跟著活著。
    package let connections: ConnectionProvider

    init(endpoint: Endpoint, settings: ClientSettings, serverInfo: ServerFeatures.ServiceInfo, connections: ConnectionProvider) {
        self.endpoint = endpoint
        self.settings = settings
        self.serverInfo = serverInfo
        self.connections = connections
    }
    
    
}
