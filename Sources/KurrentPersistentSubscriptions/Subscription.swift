//
//  Subscription.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2024/3/23.
//

import DequeModule
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportCore
import GRPCNIOTransportHTTP2Posix
import KurrentCore

extension PersistentSubscriptions {
    public final class Subscription: @unchecked Sendable {
        package typealias Request = PersistentSubscriptions.Read.UnderlyingRequest
        public typealias Element = PersistentSubscription.EventResult

        let writer: Writer

        public let subscriptionId: String?
        public let events: AsyncThrowingStream<Element, Error>

        package init(requests writer: Writer = .init(), responses reader: AsyncThrowingStream<PersistentSubscriptions.Read.Response, any Error>) async throws {
            self.writer = writer

            var iterator = reader.makeAsyncIterator()
            subscriptionId = if case let .confirmation(subscriptionId) = try await iterator.next() {
                subscriptionId
            } else {
                nil
            }

            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Element.self)
            Task {
                while let response = try await iterator.next() {
                    if case let .readEvent(event, retryCount) = response {
                        continuation.yield(.init(event: event, retryCount: retryCount))
                    }
                }
            }
            events = stream
        }

        func ack(eventIds: [UUID]) async throws {
            let id = subscriptionId?.data(using: .utf8) ?? .init()
            let usecase = PersistentSubscriptions.Ack(id: id, eventIds: eventIds)

            let messages = try usecase.requestMessages()
            writer.write(messages: messages)
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

        func nack(eventIds: [UUID], action: PersistentSubscriptions.Nack.Action, reason: String) async throws {
            let usecase = PersistentSubscriptions.Nack(id: .init(), eventIds: eventIds, action: action, reason: reason)
            try writer.write(messages: usecase.requestMessages())
        }

        public func nack(readEvents: [ReadEvent], action: PersistentSubscriptions.Nack.Action, reason: String) async throws {
            let eventIds = readEvents.map {
                if let linked = $0.linkedRecordedEvent {
                    linked.id
                } else {
                    $0.recordedEvent.id
                }
            }
            try await nack(eventIds: eventIds, action: action, reason: reason)
        }

        public func nack(readEvents: ReadEvent ..., action: PersistentSubscriptions.Nack.Action, reason: String) async throws {
            try await nack(readEvents: readEvents, action: action, reason: reason)
        }
    }
}

extension PersistentSubscriptions.Subscription {
    package struct Writer {
        package typealias MessageType = Request

        package let sender: AsyncStream<MessageType>
        package let continuation: AsyncStream<MessageType>.Continuation

        init() {
            let (stream, continuation) = AsyncStream.makeStream(of: MessageType.self)
            sender = stream
            self.continuation = continuation
        }

        public func write(_ messages: MessageType...) {
            write(messages: messages)
        }

        public func write(messages: [MessageType]) {
            for message in messages {
                continuation.yield(message)
            }
        }

        public func stop() {
            continuation.finish()
        }
    }
}
