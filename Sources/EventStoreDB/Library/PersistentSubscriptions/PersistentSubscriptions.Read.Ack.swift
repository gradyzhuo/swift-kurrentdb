//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/10.
//

import Foundation
import GRPCSupport


@available(macOS 10.15, *)
extension PersistentSubscriptions{
    public struct Ack: StreamStream{
        
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ReadReq>
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_ReadResp>
        
        let subscriptionId: String
        let eventIds: [UUID]

        public func build() throws -> [Request.UnderlyingMessage] {
            return [
                .with{
                    $0.ack = .with{
                        $0.id = subscriptionId.data(using: .utf8) ?? Data()
                        $0.ids = eventIds.map{
                            $0.toEventStoreUUID()
                        }
                    }
                }
            ]
        }
        
    }
    
    
}
