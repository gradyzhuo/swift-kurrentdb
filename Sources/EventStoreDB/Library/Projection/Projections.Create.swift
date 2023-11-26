//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/11/22.
//

import Foundation
import SwiftProtobuf

@available(macOS 13.0, *)
extension Projection {
    public struct ContinuousCreate:  UnaryUnary {
        
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_CreateResp>
        
        public let name: String
        public let query: String
        public let options: Options
        
        init(name: String, query: String, options: Options) {
            self.name = name
            self.query = query
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.build()
                $0.options.continuous.name = name
                $0.options.query = query
            }
        }
    }
}

@available(macOS 13.0, *)
extension Projection.ContinuousCreate {
    
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_Projections_CreateReq
        
        
    }
    
}
