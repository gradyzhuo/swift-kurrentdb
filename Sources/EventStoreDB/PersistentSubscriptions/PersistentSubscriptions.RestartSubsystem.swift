//
//  PersistentSubscriptions.RestartSubsystem.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPCEncapsulates

extension PersistentSubscriptionsClient {
    public struct RestartSubsystem: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Empty>
        public typealias Response = DiscardedResponse<EventStore_Client_Empty>

        public func build() throws -> EventStore_Client_Empty {
            .init()
        }
    }
}
