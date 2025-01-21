//
//  GossipClient.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import KurrentCore
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates
import NIO

public typealias UnderlyingService = EventStore_Client_Gossip_Gossip

public struct Service: GRPCConcreteClient {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias UnderlyingClient = UnderlyingService.Client<Transport>
    
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults){
        self.settings = settings
        self.callOptions = callOptions
    }
}


extension Service {
    public func read() async throws -> Read.Response {
        let usecase = Read()
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
