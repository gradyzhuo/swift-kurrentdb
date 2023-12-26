//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport
import GRPC

@available(macOS 13.0, *)
public struct OperationsClient: EventStoreClient {
    public typealias UnderlyingClient = EventStore_Client_Operations_OperationsAsyncClient
    
    public var clientSettings: ClientSettings
    public var channel: GRPCChannel
    
    
    init(settings: ClientSettings) throws {
        self.clientSettings = settings
        self.channel = try GRPCChannelPool.with(settings: settings)
    }

    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        return .init(channel: channel, defaultCallOptions: callOptions)
    }
    
}

@available(macOS 13.0, *)
extension EventStoreDB {
    public static func startScavenge(threadCount: Int32, startFromChunk: Int32, settings: ClientSettings = Self.shared.settings) async throws -> OperationsClient.ScavengeResponse{
        let client = try OperationsClient(settings: settings).underlyingClient
        
        let handler = OperationsClient.StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        let request = try handler.build()
        return try await handler.handle(response: client.startScavenge(request))
    }
}
