//
//  GossipClient.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPC
import GRPCEncapsulates
import NIO

public struct GossipClient: GRPCConcreteClient {
    public typealias UnderlyingClient = EventStore_Client_Gossip_GossipAsyncClient

    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions

    public init(channel: GRPCChannel, callOptions: CallOptions) throws {
        self.channel = channel
        self.callOptions = callOptions
    }

}

extension GossipClient {
    package func read() async throws -> [Read.Response.MemberInfo] {
        let handler = Read()
        let request = try handler.build()
        let response = try await underlyingClient.read(request)
        return try response.members.map {
            try .init(from: $0)
        }
    }
}
