//
//  Streams.Subscription.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2024/3/23.
//

import GRPCCore
import GRPCEncapsulates

extension Streams {
    public final class Subscription {
        public typealias Element = ReadEvent
        
        public let events: AsyncThrowingStream<Element, Error>
        public let subscriptionId: String?

        package init(messages: AsyncThrowingStream<Streams.Subscribe.UnderlyingResponse, any Error>) async throws {
            var iterator = messages.makeAsyncIterator()

            subscriptionId = if case let .confirmation(confirmation) = try await iterator.next()?.content {
                confirmation.subscriptionID
            } else {
                nil
            }

            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Element.self)
            Task {
                while let message = try await iterator.next() {
                    if case let .event(message) = message.content {
                        try continuation.yield(.init(message: message))
                    }
                }
            }
            events = stream
        }
    }
}
