//
//  File.swift
//
//
//  Created by 卓俊諺 on 2023/12/10.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension PersistentSubscriptionsClient{
    public struct Nack: StreamStream{
        public enum Action: Int {
            case unknown = 0
            case park = 1
            case retry = 2
            case skip = 3
            case stop = 4
            
            func toEventStoreNack() -> Request.UnderlyingMessage.Nack.Action {
                return switch self {
                case .unknown:
                    .unknown
                case .park:
                    .park
                case .retry:
                    .retry
                case .skip:
                    .skip
                case .stop:
                    .stop
                }
            }
        }
        
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ReadReq>
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_ReadResp>
        
        let subscriptionId: String
        let eventIds: [UUID]
        let action: Nack.Action
        let reason: String
        
        
        public func build() throws -> [Request.UnderlyingMessage] {
            return [
                .with{
                    $0.nack = .with{
                        $0.ids = eventIds.map{
                            $0.toEventStoreUUID()
                        }
                        $0.action = action.toEventStoreNack()
                        $0.reason = reason
                    }
                }
            ]
        }
        
    }
    
    
}
