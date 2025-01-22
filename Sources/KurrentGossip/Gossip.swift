//
//  GossipClient.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import NIO
import Logging
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import KurrentCore

public typealias UnderlyingService = EventStore_Client_Gossip_Gossip

public struct Service: GRPCConcreteService {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias UnderlyingClient = UnderlyingService.Client<Transport>
    
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup){
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}


extension Service {
    public func read() async throws -> Read.Response {
        let usecase = Read()
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
