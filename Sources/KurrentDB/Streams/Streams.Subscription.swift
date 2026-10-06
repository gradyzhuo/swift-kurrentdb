//
//  Streams.Subscription.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2024/3/23.
//

import GRPCCore
import GRPCEncapsulates
import SwiftProtobuf

extension Streams {
    /// Live subscription to a stream, delivering events as an async throwing stream.
    public struct Subscription: Sendable {
        /// Async throwing stream of events received from the server.
        public let events: AsyncThrowingStream<ReadEvent, Error>

        /// Server-assigned identifier for this subscription, if provided.
        public let subscriptionId: String?

        /// Bounded hand-off between the gRPC response handler and ``events``.
        package let messages: ResponseHandoff<Read.UnderlyingResponse>

        package init(events: AsyncThrowingStream<ReadEvent, Error>, subscriptionId: String?, messages: ResponseHandoff<Read.UnderlyingResponse>) {
            self.events = events
            self.subscriptionId = subscriptionId
            self.messages = messages
        }

        /// Cancels the subscription and terminates the event stream.
        public func cancel() {
            messages.cancel()
        }
    }
}

extension Streams.Subscription: ConnectionTerminable {
    /// The dedicated connection closed (client shutdown): wakes a producer suspended in `send`
    /// and delivers `connectionClosed` once the buffer drains. No-op if the hand-off already ended.
    package func connectionDidClose() {
        messages.finish(throwing: KurrentError.connectionClosed)
    }
}
