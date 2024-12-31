//
//  StreamClient.Subscription.swift
//
//
//  Created by Grady Zhuo on 2024/3/23.
//

import Foundation
@preconcurrency import GRPC
import GRPCEncapsulates
import SwiftProtobuf

extension StreamClient {
    public final class Subscription: AsyncSequence, Sendable {
        package typealias Read = StreamClient.Read
        public typealias AsyncIterator = EventIterator
        public typealias Element = EventAppeared

        public let eventIterator: EventIterator

        let subscriptionId: String?

        package init(readCall: GRPCAsyncServerStreamingCall<Read.Request.UnderlyingMessage, Read.Response.UnderlyingMessage>) async throws {
            var iterator = readCall.responseStream.makeAsyncIterator()
            eventIterator = .init(responseStreamIterator: iterator)

            subscriptionId = if case let .confirmation(confirmation) = try await iterator.next()?.content {
                confirmation.subscriptionID
            } else {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            eventIterator
        }
    }
}

extension StreamClient.Subscription {
    
    public struct EventIterator: AsyncIteratorProtocol, Sendable {
        public typealias Element = EventAppeared
        
        let responseStreamIterator:  GRPCAsyncResponseStream<Read.Response.UnderlyingMessage>.AsyncIterator

        init(responseStreamIterator: GRPCAsyncResponseStream<Read.Response.UnderlyingMessage>.Iterator) {
            self.responseStreamIterator = responseStreamIterator
        }

        public mutating func next() async throws -> EventAppeared? {
            var responseStreamIterator = self.responseStreamIterator
            while true {
                let response = try await responseStreamIterator.next()

                if case let .event(message) = response?.content {
                    let readEvent = try ReadEvent(message: message)
                    return .init(event: readEvent)
                }
            }
        }
    }
}

extension StreamClient.Subscription {
    public struct EventAppeared {
        public let event: ReadEvent

        init(event: ReadEvent) {
            self.event = event
        }
    }
}
