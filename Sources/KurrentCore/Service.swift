//
//  Service.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/22.
//
import GRPCEncapsulates
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import NIO

public struct Service<UnderlyingClient: UnderlyGRPCClient>: GRPCConcreteService {
    public typealias Transport = UnderlyingClient.Transport
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup){
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}
