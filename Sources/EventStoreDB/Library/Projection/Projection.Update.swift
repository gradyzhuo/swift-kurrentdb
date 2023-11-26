//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/11/26.
//

import Foundation

@available(macOS 13.0, *)
extension Projection {
    public struct Update: UnaryUnary {
//        public typealias Options = <#type#>
        
        public func build() throws -> EventStore_Client_Projections_CreateReq {
            
        }
        
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_CreateResp>
        
        
        
    }
}

@available(macOS 13.0, *)
extension Projection.Update {
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_Projections_CreateReq
        
    }
}
