//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/11.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension PersistentSubscriptionsClient {
    public struct RestartSubsystem: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Empty>
        public typealias Response = DiscardedResponse<EventStore_Client_Empty>
        
        public func build() throws -> EventStore_Client_Empty {
            return .init()
        }
        
    }
}
