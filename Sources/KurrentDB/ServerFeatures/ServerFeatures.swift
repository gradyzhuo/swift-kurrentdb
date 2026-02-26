//
//  ServerFeatures.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public final class ServerFeatures: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_ServerFeatures_ServerFeatures.Client<HTTP2ClientTransport.Posix>

    internal let endpoint: Endpoint
    internal let settings: ClientSettings
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup

    init(endpoint: Endpoint, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
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
