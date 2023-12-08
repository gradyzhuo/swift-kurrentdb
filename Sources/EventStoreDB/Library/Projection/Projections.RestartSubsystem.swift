//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation

@available(macOS 13.0, *)
extension Projections{
    public struct RestartSubsystem: UnaryUnary {
        public typealias Response = DiscardedResponse<EventStore_Client_Empty>
        
        public func build() throws -> Request.UnderlyingMessage {
            return .init()
        }
        
    }
    
}


@available(macOS 13.0, *)
extension Projections.RestartSubsystem {
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_Empty
    }
}
