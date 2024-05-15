//
//  PersistentSubscriptionsClient.Subscription.swift
//
//
//  Created by 卓俊諺 on 2024/3/23.
//

import Foundation
import GRPC
import GRPCEncapsulates

extension PersistentSubscriptionsClient {
    public final class Subscription: AsyncSequence {
        public typealias AsyncIterator = EventIterator
        public typealias Element = EventResult

        public let eventIterator: EventIterator

        var subscriptionId: String?
        let requestStream: GRPCAsyncRequestStreamWriter<Read.Request.UnderlyingMessage>

        package init(readCall: GRPCAsyncBidirectionalStreamingCall<Read.Request.UnderlyingMessage, Read.Response.UnderlyingMessage>) async throws {
            requestStream = readCall.requestStream

            var iterator = readCall.responseStream.makeAsyncIterator()
            eventIterator = .init(responseStreamIterator: iterator)

            subscriptionId = if case let .subscriptionConfirmation(confirmation) = try await iterator.next()?.content {
                confirmation.subscriptionID
            } else {
                nil
            }
        }

        public func makeAsyncIterator() -> AsyncIterator {
            eventIterator
        }

        func ack(eventIds: [UUID]) async throws {
            let id = subscriptionId?.data(using: .utf8) ?? .init()
            let handler = Ack(id: id, eventIds: eventIds)
            try await requestStream.send(handler.build())
        }

        public func ack(readEvents: [ReadEvent]) async throws {
            let eventIds = readEvents.map {
                if let linked = $0.linkedRecordedEvent {
                    linked.id
                } else {
                    $0.recordedEvent.id
                }
            }
            try await ack(eventIds: eventIds)
        }

        public func ack(readEvents: ReadEvent ...) async throws {
            try await ack(readEvents: readEvents)
        }

        func nack(eventIds: [UUID], action: Nack.Action, reason: String) async throws {
            let handler: Nack = .init(id: .init(), eventIds: eventIds, action: action, reason: reason)
            try await requestStream.send(handler.build())
        }

        public func nack(readEvents: [ReadEvent], action: Nack.Action, reason: String) async throws {
            let eventIds = readEvents.map {
                if let linked = $0.linkedRecordedEvent {
                    linked.id
                } else {
                    $0.recordedEvent.id
                }
            }
            try await nack(eventIds: eventIds, action: action, reason: reason)
        }

        public func nack(readEvents: ReadEvent ..., action: Nack.Action, reason: String) async throws {
            try await nack(readEvents: readEvents, action: action, reason: reason)
        }

        deinit {
            requestStream.finish()
        }
    }
}

extension PersistentSubscriptionsClient.Subscription {
    public struct EventIterator: AsyncIteratorProtocol {
        public typealias Element = PersistentSubscriptionsClient.Subscription.Element

        var responseStreamIterator: GRPCAsyncResponseStream<PersistentSubscriptionsClient.Read.Response.UnderlyingMessage>.AsyncIterator

        init(responseStreamIterator: GRPCAsyncResponseStream<PersistentSubscriptionsClient.Read.Response.UnderlyingMessage>.Iterator) {
            self.responseStreamIterator = responseStreamIterator
        }

        public mutating func next() async throws -> EventResult? {
            while true {
                let response = try await responseStreamIterator.next()

                if case let .event(message) = response?.content {
                    let readEvent = try ReadEvent(message: message)
                    return .init(event: readEvent, retryCount: message.retryCount)
                }
            }
        }
    }
}

extension PersistentSubscriptionsClient.Subscription {
    public struct EventResult: Sendable {
        public let event: ReadEvent
        public let retryCount: Int32

        init(event: ReadEvent, retryCount: Int32) {
            self.event = event
            self.retryCount = retryCount
        }
    }
}
