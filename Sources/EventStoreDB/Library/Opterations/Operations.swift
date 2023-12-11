//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport
import GRPC

@available(macOS 10.15, *)
public struct Operations: _GRPCClient {
    typealias UnderlyingClient = EventStore_Client_Operations_OperationsAsyncClient
    
    var clientSettings: ClientSettings
    var underlyingClient: UnderlyingClient
    
    
    init(settings: ClientSettings) throws {
        self.clientSettings = settings
        let channel = try GRPCChannelPool.with(settings: settings)
        self.underlyingClient = UnderlyingClient.init(channel: channel)
    }
    
}

@available(macOS 10.15, *)
extension EventStore {
    public static func startScavenge(threadCount: Int32, startFromChunk: Int32, settings: ClientSettings = Self.shared.settings) async throws -> Operations.ScavengeResponse{
        let client = try Operations(settings: settings).underlyingClient
        
        let handler = Operations.StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        let request = try handler.build()
        return try await handler.handle(response: client.startScavenge(request))
    }
}
