//
//  PersistentSubscriptions.ReadResponse.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/28.
//

import GRPCEncapsulates

extension PersistentSubscriptions {
    /// Server response received on the persistent subscription read stream.
    public enum ReadResponse: GRPCResponse {
        package typealias UnderlyingMessage = PersistentSubscriptions.UnderlyingService.Method.Read.Output

        /// An event delivered by the subscription along with its retry count.
        case readEvent(event: ReadEvent, retryCount: Int32)
        /// Initial handshake message confirming the subscription identifier.
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
