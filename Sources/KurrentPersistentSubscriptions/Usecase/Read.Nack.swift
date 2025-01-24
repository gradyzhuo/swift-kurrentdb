//
//  PersistentSubscriptionsClient.Read.Nack.swift
//
//
//  Created by Grady Zhuo on 2023/12/10.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct Nack: StreamRequestBuildable {
        public typealias UnderlyingRequest = UnderlyingService.Method.Read.Input
        
        public enum Action: Int, Sendable {
            case unknown = 0
            case park = 1
            case retry = 2
            case skip = 3
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
        
        internal init(id: Data, eventIds: [UUID], action: Nack.Action, reason: String) {
            self.id = id
            self.eventIds = eventIds
            self.action = action
            self.reason = reason
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            return [
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
