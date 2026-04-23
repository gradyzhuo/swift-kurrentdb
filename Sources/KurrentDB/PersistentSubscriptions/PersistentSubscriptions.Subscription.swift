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
    public final class Subscription<EventResult: SubscriptionEventResult>: Sendable {
        package typealias Request = PersistentSubscriptions.UnderlyingService.Method.Read.Input

        private let source: (stream: AsyncThrowingStream<EventResult, Error>, continuation: AsyncThrowingStream<EventResult, Error>.Continuation)
        private let tracker: SubscriptionTracker
        private let writer: Writer
        private let _eventsCache: Mutex<AsyncThrowingStream<EventResult, Error>?> = .init(nil)

        public var subscriptionId: String? {
            tracker.subscriptionId
        }

        public var lastRevision: UInt64? {
            tracker.revision
        }

        public var lastPosition: StreamPosition? {
            tracker.position
        }

        public var events: AsyncThrowingStream<EventResult, Error> {
            _eventsCache.withLock { cache in
                if let existing = cache {
                    return existing
                }

                let (stream, continuation) = AsyncThrowingStream<EventResult, Error>.makeStream()

                let task = Task {
                    do {
                        for try await subscriptionResult in source.stream {
                            let result = continuation.yield(subscriptionResult)
                            if case .terminated = result {
                                continuation.finish()
                                return
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { [writer, source, tracker] termination in
                    writer.stop()
                    source.continuation.finish()
                    task.cancel()
                    tracker.callFinishActionOnce(termination: termination)
                }

                cache = stream
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
                if let revision = eventResult.revision, let position = eventResult.position {
                    tracker.update(revision: revision, position: position)
                }
                let result = source.continuation.yield(eventResult)
                if case .terminated = result {
                    source.continuation.finish()
                }
            case let .finish(error):
                source.continuation.finish(throwing: error)
            }
        }

        internal func onFinish(perform action: @Sendable @escaping (_ termination: AsyncThrowingStream<EventResult, Error>.Continuation.Termination) -> Void) {
            tracker.update(action: action)
        }

        func ack(eventIds: [UUID]) async throws(KurrentError) {
            let usecase = PersistentSubscriptions.Ack(subscriptionId: subscriptionId, eventIds: eventIds)
            do {
                let messages = try usecase.requestMessages()
                writer.write(messages: messages)
            } catch {
                throw .internalClientError(reason: "Ack eventIds:\(eventIds) failed, cause: \(error)")
            }
        }

        public func ack(readEvents: [ReadEvent]) async throws(KurrentError) {
            let eventIds = readEvents.map {
                if let link = $0.link { link.id } else { $0.record.id }
            }
            try await ack(eventIds: eventIds)
        }

        public func ack(readEvents: ReadEvent ...) async throws(KurrentError) {
            try await ack(readEvents: readEvents)
        }

        func nack(eventIds: [UUID], action: PersistentSubscriptions.Nack.Action, reason: String) async throws(KurrentError) {
            let usecase = PersistentSubscriptions.Nack(subscriptionId: subscriptionId, eventIds: eventIds, action: action, reason: reason)
            do {
                let messages = try usecase.requestMessages()
                writer.write(messages: messages)
            } catch {
                throw .internalClientError(reason: "Nack eventIds:\(eventIds) failed, cause: \(error)")
            }
        }

        public func nack(readEvents: [ReadEvent], action: PersistentSubscriptions.Nack.Action, reason: String) async throws(KurrentError) {
            let eventIds = readEvents.map {
                if let link = $0.link { link.id } else { $0.record.id }
            }
            try await nack(eventIds: eventIds, action: action, reason: reason)
        }

        public func nack(readEvents: ReadEvent ..., action: PersistentSubscriptions.Nack.Action, reason: String) async throws(KurrentError) {
            try await nack(readEvents: readEvents, action: action, reason: reason)
        }
    }
}


extension PersistentSubscriptions.Subscription {
    package struct Writer {
        package typealias MessageType = Request

        package let sender: AsyncStream<MessageType>
        package let continuation: AsyncStream<MessageType>.Continuation

        package init() {
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
        private let _hasFinished: Mutex<Bool> = .init(false)

        var subscriptionId: String? {
            _subscriptionId.withLock { $0 }
        }

        var revision: UInt64? {
            _revision.withLock { $0 }
        }

        var position: StreamPosition? {
            _position.withLock { $0 }
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

        func callFinishActionOnce(termination: AsyncThrowingStream<EventResult, Error>.Continuation.Termination) {
            let action = _hasFinished.withLock { done -> (@Sendable (AsyncThrowingStream<EventResult, Error>.Continuation.Termination) -> Void)? in
                guard !done else { return nil }
                done = true
                return _finishAction.withLock { $0 }
            }
            action?(termination)
        }
    }
}
