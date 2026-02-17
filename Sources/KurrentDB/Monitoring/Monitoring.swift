//
//  Monitoring.swift
//  KurrentMonitoring
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public actor Monitoring: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_Monitoring_Monitoring.Client<HTTP2ClientTransport.Posix>

    public private(set) var selector: NodeSelector
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    init(selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Monitoring {
    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws(KurrentError) -> Stats.Responses {
        let node = try await selector.select()
        let usecase = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        return try await usecase.perform(node: node, callOptions: callOptions)
    }
}
