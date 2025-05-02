//
//  ServerFeatures.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct ServerFeatures: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_ServerFeatures_ServerFeatures.Client<HTTP2ClientTransport.Posix>

    public private(set) var endpoint: Endpoint
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    internal init(endpoint: Endpoint, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.endpoint = endpoint
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension ServerFeatures {    
    public func getSupportedMethods() async throws(KurrentError) -> ServiceInfo {
        let usecase = GetSupportedMethods()
        return try await usecase.perform(endpoint: endpoint, settings: settings, callOptions: callOptions)
    }
}
