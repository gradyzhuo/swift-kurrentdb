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
    /// A subscription to a stream, providing access to events and metadata.
    ///
    /// `Subscription` represents a subscription to a stream, enabling you to:
    /// - Receive events through an asynchronous throwing stream.
    /// - Access the subscription's unique identifier, if provided by the server.
    ///
    /// ## Usage
    ///
    /// Subscribing to all streams and processing events:
    /// ```swift
    /// let streams = Streams(target: StreamsTarget.all, settings: .localhost())
    /// let subscription = try await streams.subscribe(from: .start)
    /// for try await event in subscription.events {
    ///     print("Received event: \(event)")
    /// }
    /// ```
    ///
    /// - Note: This class conforms to `Sendable`, ensuring safe use across concurrency contexts.
    public struct Subscription: Sendable {
        /// An asynchronous stream delivering events or errors from the subscription.
        public let events: AsyncThrowingStream<ReadEvent, Error>

        /// The unique identifier of the subscription, if provided by the server.
        public let subscriptionId: String?

        package let continuation: AsyncThrowingStream<ReadEvent, any Error>.Continuation

        /// Initializes a `Subscription` instance with an event stream and subscription ID.
        ///
        /// - Parameters:
        ///   - events: The asynchronous stream of `ReadEvent` objects.
        ///   - subscriptionId: An optional subscription identifier.
        package init(events: AsyncThrowingStream<ReadEvent, Error>, continuation: AsyncThrowingStream<ReadEvent, any Error>.Continuation, subscriptionId: String?) {
            self.events = events
            self.continuation = continuation
            self.subscriptionId = subscriptionId
        }

        public func cancel() {
            continuation.finish()
        }
    }
}
