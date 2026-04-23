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

        package let continuation: AsyncThrowingStream<ReadEvent, any Error>.Continuation

        package let task: Task<Void, Never>?

        package init(events: AsyncThrowingStream<ReadEvent, Error>, continuation: AsyncThrowingStream<ReadEvent, any Error>.Continuation, subscriptionId: String?, task: Task<Void, Never>? = nil) {
            self.events = events
            self.continuation = continuation
            self.subscriptionId = subscriptionId
            self.task = task
        }

        /// Cancels the subscription and terminates the event stream.
        public func cancel() {
            task?.cancel()
            continuation.finish()
        }
    }
}
