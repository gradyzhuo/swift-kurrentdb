//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport


extension OperationsClient {
    
    public struct SetNodePriority: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Operations_SetNodePriorityReq>
        public typealias Response = EmptyResponse
        
        
        let priority: Int32
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.priority = priority
            }
        }
    }
    
}

