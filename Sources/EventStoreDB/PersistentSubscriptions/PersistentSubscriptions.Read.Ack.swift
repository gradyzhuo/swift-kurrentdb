//
//  PersistentSubscriptions.Read.Ack.swift
//
//
//  Created by Grady Zhuo on 2023/12/10.
//

import Foundation
import GRPCEncapsulates

extension PersistentSubscriptionsClient {
    public struct Ack: StreamStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ReadReq>
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_ReadResp>

        public let id: Data
        public let eventIds: [UUID]

        package func build() throws -> [Request.UnderlyingMessage] {
            [
                .with {
                    $0.ack = .with {
                        $0.id = id
                        $0.ids = eventIds.map {
                            $0.toEventStoreUUID()
                        }
                    }
                },
            ]
        }
    }
}

extension PersistentSubscriptionsClient.Ack {
    public struct SubscriptionConfirmation {
        let scriptionId: String
    }
}
