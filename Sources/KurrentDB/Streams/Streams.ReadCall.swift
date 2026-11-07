//
//  Streams.ReadCall.swift
//  KurrentStreams
//

import GRPCCore

extension Streams {
    /// A read that has not started yet: a cold sequence of the stream's events, delivered lazily.
    ///
    /// Iterating opens one RPC per iterator and pulls events from the server as you iterate, so
    /// memory stays bounded and the RPC ends when the iterator is released — after the loop finishes,
    /// on `break`, on a thrown error, or when the iterating task is cancelled. Iterating the same
    /// `ReadCall` again opens a new RPC and replays from the start. Use ``buffered`` to fetch the
    /// whole result before iterating.
    ///
    /// ```swift
    /// for try await response in client.streams(specified: "orders").read() { _ = response }
    /// let total = try await client.allStreams.read { $0.limit = 1000 }.reduce(0) { count, _ in count + 1 }
    /// ```
    ///
    /// Creating a `ReadCall` performs no network activity. Memory per read is bounded by the element
    /// in hand-off when iterated on an actor (one, held by the suspended producer), the transport's
    /// inbound message queue (10 messages by default) and one HTTP/2 stream flow-control window
    /// (about 8 MiB by default) — not proportional to the result size. The only way to keep the RPC
    /// open is to call `makeAsyncIterator()` yourself and hold on to the iterator.
    ///
    /// `KurrentDBClient.shutdown()` ends an iteration in progress, or one still opening its RPC, with
    /// `KurrentError.connectionClosed` at the next `next()`, also when it is called from the loop body.
    public struct ReadCall: AsyncSequence, Sendable {
        public typealias Element = Streams.ReadResponse
        public typealias Failure = any Error

        let selector: NodeSelector
        let openCall: @Sendable (Node) async throws(KurrentError) -> ScopedCall<ReadResponse>
        let bufferedRead: @Sendable () async throws(KurrentError) -> AsyncThrowingStream<ReadResponse, any Error>
        let openParkedCall: @Sendable (Node) async throws(KurrentError) -> ParkedCall<Read.UnderlyingResponse, ReadResponse>

        /// Starts an iteration. No network activity happens until the first `next()`.
        public func makeAsyncIterator() -> Iterator { Iterator(call: self) }

        /// The whole result, fetched before this returns, so memory grows with the result.
        public var buffered: AsyncThrowingStream<ReadResponse, any Error> {
            get async throws(KurrentError) { try await bufferedRead() }
        }

        /// The read itself: `read()` is lazy in 3.0.
        @available(*, deprecated, message: "read() is lazy in 3.0; drop .lazy. Removed in 4.0.")
        public var lazy: ReadCall { self }

        /// The 2.x name of the lazy read, which is now ``ReadCall`` itself.
        @available(*, deprecated, message: "Use Streams.ReadCall; removed in 4.0.")
        public typealias Lazy = ReadCall
    }
}

extension Streams.ReadCall {
    /// Iterates a read: opens its RPC on the first `next()` and ends it when released.
    ///
    /// The iterator throws exactly two error types: `KurrentError` for everything the client or the
    /// server reports, before the server accepted the call and after it — node discovery, a refused
    /// connection, a deadline, an access-denied or deleted stream, a server or transport failure,
    /// `connectionClosed` after `shutdown()` — and
    /// `CancellationError` when the iterating task is cancelled. After one throw, `next()` returns `nil`.
    /// A read that has already delivered every event may still end with `connectionClosed` if
    /// `shutdown()` races its end.
    ///
    /// Not for concurrent use: call `next()` from one task at a time. Keeping the iterator on an actor
    /// does not serialise calls from two tasks, which interleave at each suspension.
    /// Two first calls that overlap each open an RPC, and the RPC of the first is leaked; overlapping
    /// calls after that trap — on the hand-off path in its single-consumer check, on the direct path
    /// when one call finds the response iterator gone.
    ///
    /// Delivers the read along one of two paths, chosen on the first `next(isolation:)` and kept:
    /// off any actor (`isolation` nil) the consumer iterates grpc-swift's response sequence itself
    /// while the RPC handler waits (the direct path); on an actor the RPC's own task forwards each
    /// element through a hand-off and the consumer hops once per element (the hand-off path).
    /// grpc-swift forwards the isolation, but the NIO iterator underneath it has only `next()`, so on
    /// an actor the direct path would hop inside the transport per element and decode on the
    /// actor; the hand-off path avoids that. Either path is correct from any context; only the cost differs.
    public final class Iterator: AsyncIteratorProtocol {
        /// How an iterator delivers its read; `nil` before the first `next(isolation:)`.
        package enum DeliveryPath: Sendable {
            /// The consumer iterates the RPC's response sequence; the handler is parked.
            case direct
            /// The RPC's task forwards every element through a `ResponseHandoff`.
            case handoff
        }

        private enum Delivery: Sendable {
            case handoff(ScopedCall<Streams.ReadResponse>)
            case direct(ParkedCall<Streams.Read.UnderlyingResponse, Streams.ReadResponse>)

            func close() async {
                switch self {
                case let .handoff(scoped): await scoped.close()
                case let .direct(parked): await parked.close()
                }
            }

            func closeInBackground() {
                switch self {
                case let .handoff(scoped): scoped.closeInBackground()
                case let .direct(parked): parked.closeInBackground()
                }
            }
        }

        private let call: Streams.ReadCall
        private var delivery: Delivery?
        /// The direct path's iterator over the parked call's `messages`.
        private var messages: RPCAsyncSequence<Streams.Read.UnderlyingResponse, any Error>.AsyncIterator?
        private var finished = false

        /// The path this iterator delivers on; `nil` until the first `next(isolation:)`. For tests.
        package private(set) var deliveryPath: DeliveryPath?

        init(call: Streams.ReadCall) { self.call = call }

        deinit {
            // The loop ended without reaching the end (break, throw, cancellation, or the
            // iterator was dropped): end the RPC and return the lease in the background.
            if let delivery, !finished { delivery.closeInBackground() }
        }

        /// Advances the read; equivalent to `next(isolation: nil)`.
        public func next() async throws -> Streams.ReadResponse? { try await next(isolation: nil) }

        /// Advances the read on the caller's actor (`#isolation`), so an iterator kept in actor state
        /// can be advanced from that actor without leaving its isolation.
        public func next(isolation actor: isolated (any Actor)? = #isolation) async throws -> Streams.ReadResponse? {
            if finished { return nil }
            let path = deliveryPath ?? (actor == nil ? .direct : .handoff)
            deliveryPath = path
            if Task.isCancelled {
                // Cancelled before the first call or between two: finish for good, and end an
                // open RPC now instead of at deinit.
                finished = true
                if let delivery { await delivery.close() }
                throw CancellationError()
            }

            let active: Delivery
            if let delivery {
                active = delivery
            } else {
                active = try await open(path, isolation: actor)
                delivery = active
                if case let .direct(parked) = active { messages = parked.messages.makeAsyncIterator() }
            }

            switch active {
            case let .handoff(scoped):
                do {
                    if let element = try await scoped.handoff.next(isolation: actor) { return element }
                    // Either the server finished the stream or our task was cancelled (the
                    // hand-off ends quietly on consumer-side cancellation).
                    finished = true
                    await scoped.close()
                    try Task.checkCancellation()
                    return nil
                } catch {
                    finished = true
                    await scoped.close()
                    throw error
                }
            case let .direct(parked):
                var failure: (any Error)?
                do {
                    while let message = try await messages!.next(isolation: actor) {
                        // The RPC was cut off (deadline, shutdown) while messages that had
                        // already arrived were still buffered: end now, as the hand-off does.
                        if let error = parked.terminalError {
                            failure = error
                            break
                        }
                        if let element = try parked.map(message) { return element }
                    }
                } catch {
                    failure = error
                }
                // The sequence ended or failed: let the handler return, wait for the RPC, and
                // prefer its own terminal error (a deadline, shutdown) over what the iteration
                // saw of it.
                finished = true
                messages = nil
                let terminal = await parked.finish()
                if Task.isCancelled { throw CancellationError() }
                if let error = terminal ?? failure.map(parked.mapFailure) { throw error }
                return nil
            }
        }

        /// Establishes the RPC on `path`. Retry covers only this: no element has been delivered yet.
        ///
        /// `defaultDeadline` bounds the whole of it — node selection, every attempt, the wait for a
        /// stream slot and for the server's first response — as one budget (§5.1.3). A deadline
        /// before acceptance, the budget's or a caller-set `CallOptions.timeout`'s, is final: it is
        /// not retried and does not reset the cached node, although `deadlineExceeded` is a node
        /// failure for every other call.
        private func open(_ path: DeliveryPath, isolation _: isolated (any Actor)?) async throws -> Delivery {
            let call = call   // the retry closures are @Sendable; capture the value, not `self`
            let isRetryable: @Sendable (KurrentError) -> Bool = { $0.isNodeFailure && $0 != .deadlineExceeded }
            do {
                return try await withEstablishmentBudget(milliseconds: call.selector.settings.defaultDeadline, connections: call.selector.connections) { () throws(KurrentError) -> Delivery in
                    switch path {
                    case .handoff:
                        return try await .handoff(withRetry(
                            policy: call.selector.retryPolicy,
                            isRetryable: isRetryable,
                            selectNode: { try await call.selector.select() },
                            invalidate: { await call.selector.invalidate() }
                        ) { node in
                            try await call.openCall(node)
                        })
                    case .direct:
                        return try await .direct(withRetry(
                            policy: call.selector.retryPolicy,
                            isRetryable: isRetryable,
                            selectNode: { try await call.selector.select() },
                            invalidate: { await call.selector.invalidate() }
                        ) { node in
                            try await call.openParkedCall(node)
                        })
                    }
                }
            } catch {
                finished = true   // one throw ends the sequence; never reopen on the next call
                // Node discovery wraps a cancelled task as internalClientError and open()
                // as connectionClosed; the caller asked to stop either way.
                if Task.isCancelled { throw CancellationError() }
                throw error
            }
        }
    }
}
