//
//  PersistentSubscriptions.Ack.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/10.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    /// Represents a positive acknowledgement (ack) sent to a persistent subscription for one or more processed events.
    public struct Ack: StreamRequestBuildable {
        package typealias UnderlyingRequest = UnderlyingService.Method.Read.Input

        /// The raw subscription identifier used to correlate the acknowledgement with the server.
        public let id: Data
        /// The UUIDs of the events being acknowledged.
        public let eventIds: [UUID]

        init(subscriptionId id: String?, eventIds: [UUID]) {
            self.id = id.flatMap { $0.data(using: .utf8) } ?? .init()
            self.eventIds = eventIds
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
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

extension PersistentSubscriptions.Ack {
    /// Confirmation returned by the server when a persistent subscription is successfully established.
    public struct SubscriptionConfirmation {
        let scriptionId: String
    }
}
