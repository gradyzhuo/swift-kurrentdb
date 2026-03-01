//
//  Gossip.swift
//  KurrentGossip
//
//  Created by Grady Zhuo on 2023/10/17.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct Gossip: Sendable{
    package typealias UnderlyingClient = EventStore_Client_Gossip_Gossip.Client<HTTP2ClientTransport.Posix>

    public let endpoint: Endpoint
    public let settings: ClientSettings
    public let callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    init(endpoint: Endpoint, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.endpoint = endpoint
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Gossip {
    public func read(timeout _: Duration) async throws(KurrentError) -> [MemberInfo] {
        let usecase = Read()
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            try await withGRPCClient(transport: .http2NIOPosix(
                target: endpoint.target,
                transportSecurity: settings.transportSecurity
            )) { client in
                logger.debug("[\(Self.self)] Opening connection...")
                let metadata = Metadata(from: settings)
                return try await usecase.send(connection: client, metadata: metadata, callOptions: callOptions)
            }
        }
    }
}
