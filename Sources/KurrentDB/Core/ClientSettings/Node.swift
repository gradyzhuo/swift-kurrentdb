//
//  Connection.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/23.
//
import NIO
import GRPCCore
import GRPCNIOTransportHTTP2

public actor Node: Sendable{
    package let endpoint: Endpoint
    package let settings: ClientSettings
    package let nodePreference: TopologyClusterMode.NodePreference?
    package let timeout: TimeAmount
    
    init (endpoint: Endpoint, settings: ClientSettings, nodePreference: TopologyClusterMode.NodePreference = .leader, timeout: TimeAmount = DEFAULT_GOSSIP_TIMEOUT) throws(KurrentError){
        self.endpoint = endpoint
        self.settings = settings
        self.nodePreference = nodePreference
        self.timeout = timeout
    }
    
    internal func makeClient() throws(KurrentError) -> GRPCClient<HTTP2ClientTransport.Posix> {
        do{
            let transport: HTTP2ClientTransport.Posix = try .http2NIOPosix(
                                                            target: endpoint.target,
                                                            transportSecurity: settings.transportSecurity)
            return .init(transport: transport)
        }catch{
            throw .initializationError(reason: "Failed to initialize GRPCClient in \(Self.self)")
        }
    }
}
