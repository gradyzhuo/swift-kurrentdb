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
    package let serverInfo: ServerFeatures.ServiceInfo
    
    init (endpoint: Endpoint, settings: ClientSettings, serverInfo: ServerFeatures.ServiceInfo){
        self.endpoint = endpoint
        self.settings = settings
        self.serverInfo = serverInfo
    }
    
    internal func makeClient() throws(KurrentError) -> GRPCClient<HTTP2ClientTransport.Posix> {
        do{
            return try settings.makeClient(endpoint: endpoint)
        }catch{
            throw .initializationError(reason: "Failed to initialize GRPCClient in \(Self.self)")
        }
    }
}
