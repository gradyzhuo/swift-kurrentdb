//
//  ResponseHandoff.swift
//  KurrentCore
//

import Synchronization

/// Single-producer / single-consumer hand-off with a fixed capacity.
///
/// The producer (a gRPC response handler) suspends in ``send(_:)`` while `capacity` elements
/// are waiting, so it stops pulling from the transport; HTTP/2 flow control then stops the
/// server. ``finish(throwing:)`` is called by the producer, ``cancel()`` by the consumer side
/// (directly, on task cancellation, or when the stream from ``makeStream()`` is released).
/// `onTermination` runs exactly once, on whichever of the two happens first.
///
/// Cancellation is split by side. Consumer-side cancellation ends quietly: the buffer is dropped
/// and `next()` returns `nil`. Cancelling the producer's task inside ``send(_:)`` instead behaves
/// like `finish(throwing: CancellationError())`: the consumer drains the buffer and then receives
/// `CancellationError`, so truncated data never looks like a clean end. ``finish(throwing:)`` also
/// wakes a suspended producer with `CancellationError`.
package final class ResponseHandoff<Element: Sendable>: Sendable {
    private enum Terminal {
        case finished((any Error)?)
        case cancelled
    }

    private struct State {
        var buffer: [Element] = []
        var terminal: Terminal?
        var consumer: CheckedContinuation<Element?, any Error>?
        var producer: (element: Element, continuation: CheckedContinuation<Void, any Error>)?
        var sentCount = 0
        var deliveredCount = 0
    }

    private enum SendAction {
        case fail
        case resumeConsumer(CheckedContinuation<Element?, any Error>)
        case done
        case suspend
    }

    private enum NextAction {
        case deliver(Element, wake: CheckedContinuation<Void, any Error>?)
        case fail(any Error)
        case end
        case suspend
    }

    package let capacity: Int
    private let state = Mutex(State())
    private let onTermination: @Sendable ((any Error)?) -> Void

    package init(capacity: Int = 1, onTermination: @escaping @Sendable ((any Error)?) -> Void = { _ in }) {
        precondition(capacity >= 1, "ResponseHandoff capacity must be at least 1")
        self.capacity = capacity
        self.onTermination = onTermination
    }

    /// Number of elements accepted from the producer.
    package var sentCount: Int { state.withLock { $0.sentCount } }

    /// Number of elements handed to the consumer.
    package var deliveredCount: Int { state.withLock { $0.deliveredCount } }

    package func send(_ element: Element) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let action: SendAction = state.withLock { state in
                    if state.terminal != nil {
                        return .fail
                    }
                    if let consumer = state.consumer {
                        state.consumer = nil
                        state.sentCount += 1
                        state.deliveredCount += 1
                        return .resumeConsumer(consumer)
                    }
                    if state.buffer.count < capacity {
                        state.buffer.append(element)
                        state.sentCount += 1
                        return .done
                    }
                    state.producer = (element, continuation)
                    return .suspend
                }
                switch action {
                case .fail:
                    continuation.resume(throwing: CancellationError())
                case let .resumeConsumer(consumer):
                    consumer.resume(returning: element)
                    continuation.resume()
                case .done:
                    continuation.resume()
                case .suspend:
                    break
                }
            }
        } onCancel: {
            // Producer-side cancellation must not look like a clean end: the consumer drains
            // the buffer and then receives CancellationError.
            finish(throwing: CancellationError())
        }
    }

    package func next() async throws -> Element? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Element?, any Error>) in
                let action: NextAction = state.withLock { state in
                    if !state.buffer.isEmpty {
                        let element = state.buffer.removeFirst()
                        state.deliveredCount += 1
                        var wake: CheckedContinuation<Void, any Error>?
                        if let pending = state.producer {
                            state.producer = nil
                            state.buffer.append(pending.element)
                            state.sentCount += 1
                            wake = pending.continuation
                        }
                        return .deliver(element, wake: wake)
                    }
                    switch state.terminal {
                    case let .finished(error?)?:
                        // An AsyncSequence ends after throwing once.
                        state.terminal = .finished(nil)
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
                case let .deliver(element, wake):
                    wake?.resume()
                    continuation.resume(returning: element)
                case let .fail(error):
                    continuation.resume(throwing: error)
                case .end:
                    continuation.resume(returning: nil)
                case .suspend:
                    break
                }
            }
        } onCancel: {
            cancel()
        }
    }

    package func finish(throwing error: (any Error)? = nil) {
        let (first, consumer, producer): (Bool, CheckedContinuation<Element?, any Error>?, CheckedContinuation<Void, any Error>?) = state.withLock { state in
            guard state.terminal == nil else { return (false, nil, nil) }
            let consumer = state.consumer
            state.consumer = nil
            // A suspended producer's element is dropped (not counted); it is woken below.
            let producer = state.producer?.continuation
            state.producer = nil
            // A waiting consumer means the buffer is empty: hand it the outcome directly.
            state.terminal = (consumer != nil && error != nil) ? .finished(nil) : .finished(error)
            return (true, consumer, producer)
        }
        guard first else { return }
        if let consumer {
            if let error {
                consumer.resume(throwing: error)
            } else {
                consumer.resume(returning: nil)
            }
        }
        producer?.resume(throwing: CancellationError())
        onTermination(error)
    }

    package func cancel() {
        let (first, consumer, producer): (Bool, CheckedContinuation<Element?, any Error>?, CheckedContinuation<Void, any Error>?) = state.withLock { state in
            guard state.terminal == nil else { return (false, nil, nil) }
            state.terminal = .cancelled
            state.buffer.removeAll()
            let consumer = state.consumer
            let producer = state.producer?.continuation
            state.consumer = nil
            state.producer = nil
            return (true, consumer, producer)
        }
        guard first else { return }
        consumer?.resume(returning: nil)
        producer?.resume(throwing: CancellationError())
        onTermination(nil)
    }

    /// Wraps the hand-off as a pull-based stream. Call at most once per hand-off.
    ///
    /// The stream's closure holds a sentinel that cancels the hand-off when the stream is
    /// released — after `break` once it leaves scope, when dropped un-iterated, or when the
    /// consuming task is cancelled.
    package func makeStream<T: Sendable>(_ transform: @escaping @Sendable (Element) throws -> T?) -> AsyncThrowingStream<T, any Error> {
        let sentinel = CancelOnDeinit(self)
        return AsyncThrowingStream(unfolding: {
            while let element = try await sentinel.handoff.next() {
                if let value = try transform(element) {
                    return value
                }
            }
            return nil
        })
    }

    package func makeStream() -> AsyncThrowingStream<Element, any Error> {
        makeStream { $0 }
    }
}

/// Cancels its hand-off when the stream that captured it is released.
private final class CancelOnDeinit<Element: Sendable>: Sendable {
    let handoff: ResponseHandoff<Element>

    init(_ handoff: ResponseHandoff<Element>) {
        self.handoff = handoff
    }

    deinit {
        handoff.cancel()
    }
}
