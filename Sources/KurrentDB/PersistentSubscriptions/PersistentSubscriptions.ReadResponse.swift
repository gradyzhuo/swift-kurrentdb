//
//  ReadResponse.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/28.
//

import GRPCEncapsulates

extension PersistentSubscriptions {
    public enum ReadResponse: GRPCResponse {
        package typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_ReadResp

        case readEvent(event: ReadEvent, retryCount: Int32)
        case confirmation(subscriptionId: String)

        package init(from message: UnderlyingMessage) throws {
            guard let content = message.content else {
                throw KurrentError.resourceNotFound(reason: "The content of PersistentSubscriptions Read Response is missing.")
            }
            switch content {
            case let .event(eventMessage):
                self = try .readEvent(event: .init(message: eventMessage), retryCount: eventMessage.retryCount)
            case let .subscriptionConfirmation(subscriptionConfirmation):
                self = .confirmation(subscriptionId: subscriptionConfirmation.subscriptionID)
            }
        }
    }
}
