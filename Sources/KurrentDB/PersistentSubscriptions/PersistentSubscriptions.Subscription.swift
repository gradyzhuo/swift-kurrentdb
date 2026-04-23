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
import Synchronization

extension PersistentSubscriptions {
    public final class Subscription<EventResult: Sendable>: Sendable {
        package typealias Request = PersistentSubscriptions.UnderlyingService.Method.Read.Input
        
        private let source: (stream: AsyncThrowingStream<EventResult, Error>, continuation: AsyncThrowingStream<EventResult, Error>.Continuation)
        private let tracker: SubscriptionTracker
        private let writer: Writer
        
        public var subscriptionId: String? {
            get{
                tracker.subscriptionId
            }
        }
        
        public var events: AsyncThrowingStream<EventResult, Error>{
            get{
                let (stream, continuation) = AsyncThrowingStream<EventResult, Error>.makeStream()
                
                let task = Task{
                    do{
                        for try await subscriptionResult in source.stream {
                            let result = continuation.yield(subscriptionResult)
                            if case .terminated = result {
                                continuation.finish()
                            }
                        }
                        continuation.finish()
                    }catch{
                        continuation.finish(throwing: error)
                    }
                }
                
                continuation.onTermination = { [writer, source, tracker] termination in
                    // 不管 .finished 還是 .cancelled，都要通知 grpc 端停止
                    writer.stop()
                    source.continuation.finish()
                    task.cancel()
                    tracker.finishAction?(termination)
                }
                
                
                return stream
            }
        }
        
        init(writer: Writer) {
            self.writer = writer
            self.tracker = SubscriptionTracker()
            self.source = AsyncThrowingStream<EventResult, Error>.makeStream()
        }
        
        internal func send(state: State) {
            switch state {
            case let .confirmation(subscriptionId):
                tracker.update(subscriptionId: subscriptionId)
            case let .response(eventResult):
                let result = source.continuation.yield(eventResult)
                // ✅ 檢查 yield 結果
                if case .terminated = result {
                    // consumer 跑了，通知上游停止
                    source.continuation.finish()
                }
            case let .finish(error):
                source.continuation.finish(throwing: error)
            }
        }
        
        internal func onFinish(perform action: @Sendable @escaping (_ termination: AsyncThrowingStream<EventResult, Error>.Continuation.Termination) -> Void) {
            tracker.update(action: action)
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
    
    enum State: Sendable {
        case confirmation(subscriptionId: String)
        case response(eventResult: EventResult)
        case finish(throwing: (any Error)?)
        
        internal static func finish() -> Self {
            .finish(throwing: nil)
        }
    }
    
    private final class SubscriptionTracker: Sendable {
        private let _revision: Mutex<UInt64?> = .init(nil)
        private let _position: Mutex<StreamPosition?> = .init(nil)
        private let _subscriptionId: Mutex<String?> = .init(nil)
        private let _finishAction: Mutex<(@Sendable (_ termination: AsyncThrowingStream<EventResult, Error>.Continuation.Termination) -> Void)?> = .init(nil)

        var subscriptionId: String? {
            _subscriptionId.withLock { $0 }
        }
        
        var revision: UInt64? {
            _revision.withLock { $0 }
        }

        var position: StreamPosition? {
            _position.withLock { $0 }
        }
        
        var finishAction: (@Sendable (_ termination: AsyncThrowingStream<EventResult, Error>.Continuation.Termination) -> Void)? {
            _finishAction.withLock { $0 }
        }
        
        func update(subscriptionId: String) {
            _subscriptionId.withLock { $0 = subscriptionId }
        }
        
        func update(action: @escaping @Sendable (_ termination: AsyncThrowingStream<EventResult, Error>.Continuation.Termination) -> Void) {
            _finishAction.withLock { $0 = action }
        }

        func update(revision: UInt64, position: StreamPosition) {
            _revision.withLock { $0 = revision }
            _position.withLock { $0 = position }
        }
    }
}
