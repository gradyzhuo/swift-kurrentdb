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
    /// Run when the dedicated connection closes (client shutdown): wakes a producer suspended in
    /// `send` and ends the stream with `connectionClosed`; an element the producer was holding is
    /// dropped. No-op if the hand-off already
    /// ended. Captures only the hand-off, never the subscription (see ``ConnectionTerminable``).
    package var connectionCloseHandler: @Sendable () -> Void {
        { [messages] in messages.finish(throwing: KurrentError.connectionClosed) }
    }
}
