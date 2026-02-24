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

    init(endpoint: Endpoint, settings: ClientSettings, serverInfo: ServerFeatures.ServiceInfo) {
        self.endpoint = endpoint
        self.settings = settings
        self.serverInfo = serverInfo
    }
    
    
}
