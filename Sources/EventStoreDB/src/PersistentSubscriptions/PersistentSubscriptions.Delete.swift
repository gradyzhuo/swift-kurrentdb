//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension PersistentSubscriptionsClient {
    
    public struct Delete: UnaryUnary {
        
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_DeleteResp>
        
        
        let streamSelection: StreamSelection
        let groupName: String
        
        public func build() throws -> Request.UnderlyingMessage {
            return try .with{
                $0.options.groupName = groupName
                switch streamSelection {
                case .all:
                    $0.options.all = .init()
                case .specified(let streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                }
            }
            
        }
    }
}

@available(macOS 13.0, *)
extension PersistentSubscriptionsClient.Delete{
    
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_DeleteReq
        
        
    }
    
}


