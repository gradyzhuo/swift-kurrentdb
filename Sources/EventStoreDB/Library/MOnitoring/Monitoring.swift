//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/11.
//

import Foundation
import GRPCSupport
import GRPC


@available(macOS 10.15, *)
public struct Monitoring: _GRPCClient {
    typealias UnderlyingClient = EventStore_Client_Monitoring_MonitoringAsyncClient
    
    var clientSettings: ClientSettings
    var underlyingClient: UnderlyingClient
    
    public init(settings: ClientSettings = EventStore.shared.settings) throws {
        self.clientSettings = settings
        let channel = try GRPCChannelPool.with(settings: settings)
        self.underlyingClient = .init(channel: channel)
    }
    
    
    
    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws -> AsyncStream<Stats.Response>{
        let handler = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        let request = try handler.build()
        let responses = underlyingClient.stats(request)
        
        return .init { continuation in
            Task{
                for try await response in responses {
                    continuation.yield( try .init(from: response))
                }
                continuation.finish()
            }
        }
        
    }
}
