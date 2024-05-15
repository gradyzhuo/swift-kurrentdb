//
//  PersistentSubscriptions.Read.Nack.swift
//
//
//  Created by Grady Zhuo on 2023/12/10.
//

import Foundation
import GRPCEncapsulates

extension PersistentSubscriptionsClient {
    public struct Nack: StreamStream {
        public enum Action: Int {
            case unknown = 0
            case park = 1
            case retry = 2
            case skip = 3
            case stop = 4

            func toEventStoreNack() -> Request.UnderlyingMessage.Nack.Action {
                switch self {
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

        let id: Data
        let eventIds: [UUID]
        let action: Nack.Action
        let reason: String

        package func build() throws -> [Request.UnderlyingMessage] {
            [
                .with {
                    $0.nack = .with {
                        $0.id = id
                        $0.ids = eventIds.map {
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
