//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import GRPCSupport


extension ProjectionsClient{
    public struct RestartSubsystem: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Empty>
        public typealias Response = DiscardedResponse<EventStore_Client_Empty>
        
        public func build() throws -> Request.UnderlyingMessage {
            return .init()
        }
        
    }
    
}
