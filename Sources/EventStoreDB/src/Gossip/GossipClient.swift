//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation
import GRPC
import NIO
import GRPCSupport


public struct GossipClient: EventStoreClient {
    public typealias UnderlyingClient = EventStore_Client_Gossip_GossipAsyncClient
    
    public var clientSettings: ClientSettings
    public var channel: GRPCChannel
    
    public init(settings: ClientSettings = EventStoreDB.shared.settings) throws {
        self.clientSettings = settings
        self.channel = try GRPCChannelPool.with(settings: settings)
    }
    
    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        return .init(channel: channel, defaultCallOptions: callOptions)
    }
    
    
}


extension GossipClient {
    
    public static func read() async throws -> [Read.Response.MemberInfo] {
        let handler = Read()
        let request = try handler.build()
        let client = try Self.init()
        let response = try await client.underlyingClient.read(request)
        return try response.members.map{
            try .init(from: $0)
        }
        
    }
}




