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
    /// let streams = Streams(target: StreamTarget.all, settings: .localhost())
    /// let subscription = try await streams.subscribe(from: .start)
    /// for try await event in subscription.events {
    ///     print("Received event: \(event)")
    /// }
    /// ```
    ///
    /// - Note: This class conforms to `Sendable`, ensuring safe use across concurrency contexts.
    public final class Subscription: Sendable {
        /// An asynchronous stream delivering events or errors from the subscription.
        public let events: AsyncThrowingStream<ReadEvent, Error>
        
        /// The unique identifier of the subscription, if provided by the server.
        public let subscriptionId: String?
        
        public let continuation: AsyncThrowingStream<ReadEvent, any Error>.Continuation
        
        /// Initializes a `Subscription` instance with an event stream and subscription ID.
        ///
        /// - Parameters:
        ///   - events: The asynchronous stream of `ReadEvent` objects.
        ///   - subscriptionId: An optional subscription identifier.
        private init(events: AsyncThrowingStream<ReadEvent, Error>, continuation: AsyncThrowingStream<ReadEvent, any Error>.Continuation, subscriptionId: String?) {
            self.events = events
            self.continuation = continuation
            self.subscriptionId = subscriptionId
        }
    }
}

/// Provides a convenience initializer for subscriptions targeting all streams.
extension Streams.Subscription where Target == AllStreams {
    /// Initializes a subscription for all streams from a response message stream.
    ///
    /// This initializer processes an asynchronous stream of responses from a `SubscribeAll` request,
    /// extracting the subscription ID from the first confirmation message and yielding `ReadEvent`
    /// instances to the `events` stream.
    ///
    /// - Parameter messages: An asynchronous stream of `Streams.SubscribeAll.UnderlyingResponse` objects.
    /// - Throws: An error if the response stream cannot be processed or event conversion fails.
    package convenience init(messages: AsyncThrowingStream<Streams.SubscribeAll.UnderlyingResponse, any Error>) async throws {
        var iterator = messages.makeAsyncIterator()

        let subscriptionId: String? = if case let .confirmation(confirmation) = try await iterator.next()?.content {
            confirmation.subscriptionID
        } else {
            nil
        }

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ReadEvent.self)
        
        Task {
            do{
                while let message = try await iterator.next() {
                    if case let .event(message) = message.content {
                        try continuation.yield(.init(message: message))
                    }
                }
            }catch{
                continuation.finish(throwing: KurrentError.subscriptionTerminated(subscriptionId: subscriptionId, origin: error))
            }
            
        }
        let events = stream
        self.init(events: events, continuation: continuation, subscriptionId: subscriptionId)
    }
    
    public func terminate() {
        continuation.finish()
    }
}

extension Streams.Subscription{
    package convenience init(messages: AsyncThrowingStream<Streams.Subscribe.UnderlyingResponse , any Error>) async throws {
        var iterator = messages.makeAsyncIterator()

        let subscriptionId: String? = if case let .confirmation(confirmation) = try await iterator.next()?.content {
            confirmation.subscriptionID
        } else {
            nil
        }

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: ReadEvent.self)
        Task {
            while let message = try await iterator.next() {
                if case let .event(message) = message.content {
                    try continuation.yield(.init(message: message))
                }
            }
        }
        let events = stream
        self.init(events: events, continuation: continuation, subscriptionId: subscriptionId)
    }
}
