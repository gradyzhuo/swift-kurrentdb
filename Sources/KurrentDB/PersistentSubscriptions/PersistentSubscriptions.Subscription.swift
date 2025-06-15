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

extension PersistentSubscriptions {
    /// A subscription to a persistent event stream, enabling reading and acknowledging events.
    ///
    /// This class provides an interface to interact with a persistent subscription, allowing you to:
    /// - Receive events via an asynchronous stream.
    /// - Acknowledge (`ack`) or negatively acknowledge (`nack`) events.
    /// - Manage subscription lifecycle through a writer for sending requests.
    public final class Subscription: Sendable {
        /// The underlying request type for the subscription.
        package typealias Request = PersistentSubscriptions.UnderlyingService.Method.Read.Input

        /// The writer responsible for sending requests to the subscription service.
        let writer: Writer

        /// The unique identifier of the subscription, if available.
        ///
        /// This is set during initialization based on the first response from the server.
        public let subscriptionId: String?

        /// An asynchronous stream delivering events or errors from the subscription.
        public let events: AsyncThrowingStream<PersistentSubscription.EventResult, Error>

        /// Initializes a new subscription with a writer and response stream.
        ///
        /// - Parameters:
        ///   - writer: The `Writer` instance used to send requests. Defaults to a new `Writer`.
        ///   - reader: An asynchronous stream of responses from the subscription service.
        /// - Throws: An error if the initialization process fails, such as when the response stream cannot be processed.
        package init(requests writer: Writer = .init(), responses reader: AsyncThrowingStream<PersistentSubscriptions.ReadResponse, any Error>) async throws {
            self.writer = writer

            var iterator = reader.makeAsyncIterator()
            subscriptionId = if case let .confirmation(subscriptionId) = try await iterator.next() {
                subscriptionId
            } else {
                nil
            }

            let (stream, continuation) = AsyncThrowingStream.makeStream(of: PersistentSubscription.EventResult.self)
            Task {
                while let response = try await iterator.next() {
                    if case let .readEvent(event, retryCount) = response {
                        continuation.yield(.init(event: event, retryCount: retryCount))
                    }
                }
            }
            events = stream
        }

        /// Acknowledges a list of events by their UUIDs.
        ///
        /// - Parameters:
        ///   - eventIds: An array of `UUID` identifiers for the events to acknowledge.
        /// - Throws: An error if the acknowledgment request fails.
        func ack(eventIds: [UUID]) async throws(KurrentError) {
            let usecase = PersistentSubscriptions.Ack(subscriptionId: subscriptionId, eventIds: eventIds)

            do {
                let messages = try usecase.requestMessages()
                writer.write(messages: messages)
            } catch {
                throw .internalClientError(reason: "Ack eventIds:\(eventIds) failed, cause: \(error)")
            }
        }

        /// Acknowledges a list of read events.
        ///
        /// This method extracts event IDs from the provided `ReadEvent` objects and calls `ack(eventIds:)`.
        ///
        /// - Parameter readEvents: An array of `ReadEvent` objects to acknowledge.
        /// - Throws: An error if the acknowledgment process fails.
        public func ack(readEvents: [ReadEvent]) async throws(KurrentError) {
            let eventIds = readEvents.map {
                if let link = $0.link {
                    link.id
                } else {
                    $0.record.id
                }
            }
            try await ack(eventIds: eventIds)
        }

        /// Acknowledges a variadic list of read events.
        ///
        /// - Parameter readEvents: A variadic list of `ReadEvent` objects to acknowledge.
        /// - Throws: An error if the acknowledgment process fails.
        public func ack(readEvents: ReadEvent ...) async throws(KurrentError) {
            try await ack(readEvents: readEvents)
        }

        /// Negatively acknowledges a list of events by their UUIDs.
        ///
        /// - Parameters:
        ///   - eventIds: An array of `UUID` identifiers for the events to negatively acknowledge.
        ///   - action: The action to take for the negatively acknowledged events.
        ///   - reason: A string explaining why the events are negatively acknowledged.
        /// - Throws: An error if the negative acknowledgment request fails.
        func nack(eventIds: [UUID], action: PersistentSubscriptions.Nack.Action, reason: String) async throws(KurrentError) {
            let usecase = PersistentSubscriptions.Nack(subscriptionId: subscriptionId, eventIds: eventIds, action: action, reason: reason)
            do {
                let messages = try usecase.requestMessages()
                writer.write(messages: messages)
            } catch {
                throw .internalClientError(reason: "Nack eventIds:\(eventIds) failed, cause: \(error)")
            }
        }

        /// Negatively acknowledges a list of read events.
        ///
        /// This method extracts event IDs from the provided `ReadEvent` objects and calls `nack(eventIds:action:reason:)`.
        ///
        /// - Parameters:
        ///   - readEvents: An array of `ReadEvent` objects to negatively acknowledge.
        ///   - action: The action to take for the negatively acknowledged events.
        ///   - reason: A string explaining why the events are negatively acknowledged.
        /// - Throws: An error if the negative acknowledgment process fails.
        public func nack(readEvents: [ReadEvent], action: PersistentSubscriptions.Nack.Action, reason: String) async throws(KurrentError) {
            let eventIds = readEvents.map {
                if let link = $0.link {
                    link.id
                } else {
                    $0.record.id
                }
            }
            try await nack(eventIds: eventIds, action: action, reason: reason)
        }

        /// Negatively acknowledges a variadic list of read events.
        ///
        /// - Parameters:
        ///   - readEvents: A variadic list of `ReadEvent` objects to negatively acknowledge.
        ///   - action: The action to take for the negatively acknowledged events.
        ///   - reason: A string explaining why the events are negatively acknowledged.
        /// - Throws: An error if the negative acknowledgment process fails.
        public func nack(readEvents: ReadEvent ..., action: PersistentSubscriptions.Nack.Action, reason: String) async throws(KurrentError) {
            try await nack(readEvents: readEvents, action: action, reason: reason)
        }
    }
}

extension PersistentSubscriptions.Subscription {
    /// A utility struct for writing requests to the subscription service.
    package struct Writer {
        /// The type of messages this writer handles.
        package typealias MessageType = Request

        /// An asynchronous stream of messages to be sent.
        package let sender: AsyncStream<MessageType>

        /// The continuation used to yield messages to the `sender` stream.
        package let continuation: AsyncStream<MessageType>.Continuation

        /// Initializes a new writer with an asynchronous stream for sending messages.
        package init() {
            let (stream, continuation) = AsyncStream.makeStream(of: MessageType.self)
            sender = stream
            self.continuation = continuation
        }

        /// Writes a variadic list of messages to the subscription service.
        ///
        /// - Parameter messages: A variadic list of messages to write.
        public func write(_ messages: MessageType...) {
            write(messages: messages)
        }

        /// Writes an array of messages to the subscription service.
        ///
        /// - Parameter messages: An array of messages to write.
        public func write(messages: [MessageType]) {
            for message in messages {
                continuation.yield(message)
            }
        }

        /// Stops the writer by finishing the underlying stream.
        public func stop() {
            continuation.finish()
        }
    }
}
