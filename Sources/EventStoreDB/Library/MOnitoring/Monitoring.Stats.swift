//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/11.
//

import Foundation
import GRPCSupport

@available(macOS 10.15, *)
extension Monitoring {
    public struct Stats: UnaryStream{
        
        public typealias Request = GenericGRPCRequest<EventStore_Client_Monitoring_StatsReq>
        
        let useMetadata: Bool
        let refreshTimePeriodInMs: UInt64
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.useMetadata = useMetadata
                $0.refreshTimePeriodInMs = refreshTimePeriodInMs
            }
        }
        
    }
    
}

@available(macOS 10.15, *)
extension Monitoring.Stats {
    public struct Response: GRPCResponse {
        
        public typealias UnderlyingMessage = EventStore_Client_Monitoring_StatsResp
        
        var stats: [String:String]
        
        public init(from message: UnderlyingMessage) throws {
            self.stats = message.stats
        }
    
    }
}

