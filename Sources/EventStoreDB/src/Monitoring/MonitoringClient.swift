//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/11.
//

import Foundation
import GRPCSupport
import GRPC



public struct MonitoringClient: EventStoreClient {
    public typealias UnderlyingClient = EventStore_Client_Monitoring_MonitoringAsyncClient
    
    public var clientSettings: ClientSettings
    public var channel: GRPCChannel
    
    public init(settings: ClientSettings = EventStoreDB.shared.settings) throws {
        self.clientSettings = settings
        self.channel = try GRPCChannelPool.with(settings: settings)
    }
    
    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        return .init(channel: channel, defaultCallOptions: callOptions)
    }
    
    
    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws -> AsyncStream<Stats.Response>{
        let handler = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        let request = try handler.build()
        let responses = try underlyingClient.stats(request)
        
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
