//
//  PersistentSubscriptions.Nack.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/10.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    /// Represents a negative acknowledgement (nack) sent to a persistent subscription, instructing the server how to handle the specified events.
    public struct Nack: StreamRequestBuildable {
        package typealias UnderlyingRequest = UnderlyingService.Method.Read.Input

        /// The action the server should take for nack'd events.
        public enum Action: Int, Sendable {
            /// The action is unknown or unspecified.
            case unknown = 0
            /// Park the event in the dead-letter queue.
            case park = 1
            /// Retry delivering the event.
            case retry = 2
            /// Skip the event without further processing.
            case skip = 3
            /// Stop the persistent subscription.
            case stop = 4

            func toEventStoreNack() -> UnderlyingRequest.Nack.Action {
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

        let id: Data
        let eventIds: [UUID]
        let action: Nack.Action
        let reason: String

        init(subscriptionId id: String?, eventIds: [UUID], action: Nack.Action, reason: String) {
            self.id = id.flatMap { $0.data(using: .utf8) } ?? .init()
            self.eventIds = eventIds
            self.action = action
            self.reason = reason
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
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
                },
            ]
        }
    }
}
