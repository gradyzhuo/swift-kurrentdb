//
//  GossipClient.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPC
import GRPCSupport
import NIO

public struct GossipClient: EventStoreClient {
    public typealias UnderlyingClient = EventStore_Client_Gossip_GossipAsyncClient

    public var clientSettings: ClientSettings
    public var channel: GRPCChannel

    public init(settings: ClientSettings = EventStoreDB.shared.settings) throws {
        clientSettings = settings
        channel = try GRPCChannelPool.with(settings: settings)
    }

    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        .init(channel: channel, defaultCallOptions: callOptions)
    }
}

extension GossipClient {
    public static func read() async throws -> [Read.Response.MemberInfo] {
        let handler = Read()
        let request = try handler.build()
        let client = try Self()
        let response = try await client.underlyingClient.read(request)
        return try response.members.map {
            try .init(from: $0)
        }
    }
}
