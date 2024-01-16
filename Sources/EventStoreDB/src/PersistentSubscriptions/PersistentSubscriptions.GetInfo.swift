//
//  PersistentSubscriptions.GetInfo.swift
//
//
//  Created by Grady Zhuo on 2023/12/10.
//

import Foundation
import GRPCSupport

extension PersistentSubscriptionsClient {
    public struct GetInfo: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_GetInfoReq>

        let streamSelection: StreamSelection
        let groupName: String

        public func build() throws -> Request.UnderlyingMessage {
            try .with {
                switch streamSelection {
                case let .specified(streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                case .all:
                    $0.options.all = .init()
                }
                $0.options.groupName = groupName
            }
        }
    }
}

extension PersistentSubscriptionsClient.GetInfo {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_GetInfoResp

        public let subscriptionInfo: PersistentSubscriptionsClient.SubscriptionInfo

        public init(from message: UnderlyingMessage) throws {
            subscriptionInfo = .init(from: message.subscriptionInfo)
        }
    }
}
