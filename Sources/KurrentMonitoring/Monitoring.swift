//
//  MonitoringClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import NIO
import Logging
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import KurrentCore

public typealias UnderlyingService = EventStore_Client_Monitoring_Monitoring

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
    package func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws -> Stats.Responses {
        let usecase = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
