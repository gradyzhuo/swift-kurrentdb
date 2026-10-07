//
//  ResponseHandoff.swift
//  KurrentCore
//

import Synchronization

/// Single-producer / single-consumer rendezvous: an element changes hands only when both sides
/// are present.
///
/// The producer (a gRPC response handler) hands its element to a consumer waiting in ``next()``;
/// if none is waiting it suspends in ``send(_:)`` holding the element, so it stops pulling from
/// the transport and HTTP/2 flow control stops the server. There is deliberately no buffer: the
/// server sends one event per message and the producer forwards them one at a time, so a buffer
/// could only smooth speed jitter between the two sides — and the transport's own inbound queue
/// already does that. Memory held here is therefore at most one element.
///
/// ``finish(throwing:)`` is called by the producer's owner, ``cancel()`` by the consumer side
/// (directly, on task cancellation, or when the stream from ``makeStream()`` is released).
/// `onTermination` runs exactly once, on whichever of the two happens first.
///
/// Cancellation is split by side. Consumer-side cancellation ends quietly: `next()` returns `nil`.
/// Cancelling the producer's task wakes a producer suspended in ``send(_:)`` with
/// `CancellationError` and makes every later `send` fail the same way, but it does not end the
/// hand-off: the owner of the producer decides the terminal error. That matters because grpc-swift
/// enforces an RPC deadline by cancelling the response handler's task, so the owner can still
/// finish with the RPC's real final error (for example `deadlineExceeded`) instead of a
/// `CancellationError`. ``finish(throwing:)`` also wakes a suspended producer with
/// `CancellationError`; the element it was holding is dropped.
package final class ResponseHandoff<Element: Sendable>: Sendable {
    private enum Terminal {
        case finished((any Error)?)
        case cancelled
    }

    private struct State {
        var terminal: Terminal?
        var consumer: CheckedContinuation<Element?, any Error>?
        var producer: (element: Element, continuation: CheckedContinuation<Void, any Error>)?
        var producerCancelled = false
        var deliveredCount = 0
        /// Released as soon as it is taken, so whatever it captures is not kept alive by a finished hand-off.
        var onTermination: (@Sendable ((any Error)?) -> Void)?
    }

    private enum SendAction {
        case fail
        case resumeConsumer(CheckedContinuation<Element?, any Error>)
        case suspend
    }

    private enum NextAction {
        case deliver(Element, wake: CheckedContinuation<Void, any Error>)
        case fail(any Error)
        case end
        case suspend
    }

    private let state: Mutex<State>

    package init(onTermination: @escaping @Sendable ((any Error)?) -> Void = { _ in }) {
        var initial = State()
        initial.onTermination = onTermination
        state = Mutex(initial)
    }

    /// Number of elements handed to the consumer.
    package var deliveredCount: Int { state.withLock { $0.deliveredCount } }

    /// Whether the producer is suspended in ``send(_:)`` holding an element — the observable
    /// form of backpressure: nothing more is pulled from the transport until the consumer calls ``next()``.
    package var isProducerWaiting: Bool { state.withLock { $0.producer != nil } }

    package func send(_ element: Element) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let action: SendAction = state.withLock { state in
                    if state.terminal != nil || state.producerCancelled { return .fail }
                    if let consumer = state.consumer {
                        state.consumer = nil
                        state.deliveredCount += 1
                        return .resumeConsumer(consumer)
                    }
                    precondition(state.producer == nil, "ResponseHandoff supports a single producer")
                    state.producer = (element, continuation)
                    return .suspend
                }
                switch action {
                case .fail: continuation.resume(throwing: CancellationError())
                case let .resumeConsumer(consumer): consumer.resume(returning: element); continuation.resume()
                case .suspend: break
                }
            }
        } onCancel: {
            // Wake the suspended producer and refuse further sends, but leave the hand-off open:
            // the producer's owner finishes it with the RPC's real final error.
            let producer: CheckedContinuation<Void, any Error>? = state.withLock { state in
                state.producerCancelled = true
                let producer = state.producer?.continuation
                state.producer = nil
                return producer
            }
            producer?.resume(throwing: CancellationError())
        }
    }

    package func next() async throws -> Element? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Element?, any Error>) in
                let action: NextAction = state.withLock { state in
                    if let pending = state.producer {
                        state.producer = nil
                        state.deliveredCount += 1
                        return .deliver(pending.element, wake: pending.continuation)
                    }
                    switch state.terminal {
                    case let .finished(error?)?:
                        state.terminal = .finished(nil)   // an AsyncSequence ends after throwing once
                        return .fail(error)
                    case .finished(nil)?, .cancelled?:
                        return .end
                    case nil:
                        precondition(state.consumer == nil, "ResponseHandoff supports a single consumer")
                        state.consumer = continuation
                        return .suspend
                    }
                }
                switch action {
                case let .deliver(element, wake): wake.resume(); continuation.resume(returning: element)
                case let .fail(error): continuation.resume(throwing: error)
                case .end: continuation.resume(returning: nil)
                case .suspend: break
                }
            }
        } onCancel: {
            cancel()
        }
    }

    package func finish(throwing error: (any Error)? = nil) {
        let (callback, consumer, producer): ((@Sendable ((any Error)?) -> Void)?, CheckedContinuation<Element?, any Error>?, CheckedContinuation<Void, any Error>?) = state.withLock { state in
            guard state.terminal == nil else { return (nil, nil, nil) }
            let consumer = state.consumer
            let producer = state.producer?.continuation
            state.consumer = nil
            state.producer = nil
            // A waiting consumer is handed the outcome directly; leave the terminal error-free so
            // the error is not delivered twice.
            state.terminal = (consumer != nil && error != nil) ? .finished(nil) : .finished(error)
            let callback = state.onTermination
            state.onTermination = nil
            return (callback, consumer, producer)
        }
        guard let callback else { return }
        if let consumer {
            if let error { consumer.resume(throwing: error) } else { consumer.resume(returning: nil) }
        }
        producer?.resume(throwing: CancellationError())
        callback(error)
    }

    package func cancel() {
        let (callback, consumer, producer): ((@Sendable ((any Error)?) -> Void)?, CheckedContinuation<Element?, any Error>?, CheckedContinuation<Void, any Error>?) = state.withLock { state in
            switch state.terminal {
            case .cancelled?:
                return (nil, nil, nil)
            case .finished?:
                // The producer already ended and onTermination already fired, but the consumer
                // side still drops a pending error: a stream that escapes its scope must end at
                // once instead of delivering it.
                state.terminal = .cancelled
                return (nil, nil, nil)
            case nil:
                state.terminal = .cancelled
                let consumer = state.consumer
                let producer = state.producer?.continuation
                state.consumer = nil
                state.producer = nil
                let callback = state.onTermination
                state.onTermination = nil
                return (callback, consumer, producer)
            }
        }
        guard let callback else { return }
        consumer?.resume(returning: nil)
        producer?.resume(throwing: CancellationError())
        callback(nil)
    }

    /// Wraps the hand-off as a pull-based stream. Call at most once per hand-off.
    ///
    /// The stream's closure holds a sentinel that cancels the hand-off when the stream is
    /// released. An error thrown by `next()` or by `transform` also cancels it: an unfolding
    /// stream keeps its closure after throwing, so without this the hand-off would stay alive.
    package func makeStream<T: Sendable>(_ transform: @escaping @Sendable (Element) throws -> T?) -> AsyncThrowingStream<T, any Error> {
        let sentinel = CancelOnDeinit(self)
        return AsyncThrowingStream(unfolding: {
            do {
                while let element = try await sentinel.handoff.next() {
                    if let value = try transform(element) { return value }
                }
                return nil
            } catch {
                sentinel.handoff.cancel()
                throw error
            }
        })
    }

    package func makeStream() -> AsyncThrowingStream<Element, any Error> {
        makeStream { $0 }
    }
}

/// Cancels its hand-off when the stream that captured it is released.
private final class CancelOnDeinit<Element: Sendable>: Sendable {
    let handoff: ResponseHandoff<Element>
    init(_ handoff: ResponseHandoff<Element>) { self.handoff = handoff }
    deinit { handoff.cancel() }
}
