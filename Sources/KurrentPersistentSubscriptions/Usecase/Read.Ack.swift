//
//  PersistentSubscriptionsClient.Read.Ack.swift
//
//
//  Created by Grady Zhuo on 2023/12/10.
//

import Foundation
import KurrentCore
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct Ack: StreamRequestBuildable {
        public typealias UnderlyingRequest = UnderlyingService.Method.Read.Input

        public let id: Data
        public let eventIds: [UUID]
        
        internal init(id: Data, eventIds: [UUID]) {
            self.id = id
            self.eventIds = eventIds
        }
        
        package func requestMessages() throws -> [UnderlyingRequest] {
            return [
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

extension PersistentSubscriptions.Ack {
    public struct SubscriptionConfirmation {
        let scriptionId: String
    }
}
