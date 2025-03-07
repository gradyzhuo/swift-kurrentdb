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
    public final class Subscription {
        public let events: AsyncThrowingStream<ReadEvent, Error>
        public let subscriptionId: String?
        
        internal init(events: AsyncThrowingStream<ReadEvent, Error>, subscriptionId: String?) {
            self.events = events
            self.subscriptionId = subscriptionId
        }
    }
}

extension Streams.Subscription where Target == AllStreams {
    package convenience init(messages: AsyncThrowingStream<Streams.SubscribeAll.UnderlyingResponse, any Error>) async throws {
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
        self.init(events: events, subscriptionId: subscriptionId)
    }
}
