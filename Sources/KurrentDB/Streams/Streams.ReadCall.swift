//
//  Streams.ReadCall.swift
//  KurrentStreams
//

import GRPCCore

extension Streams {
    /// A read that has not started yet. Choose how its events are delivered:
    ///
    /// - ``lazy``: events are pulled from the server as you iterate, memory stays bounded, and
    ///   the RPC ends when the iterator is released.
    /// - ``buffered``: the whole result is fetched first, exactly like `read()`.
    ///
    /// ```swift
    /// for try await response in client.streams(specified: "orders").read().lazy { _ = response }
    /// let total = try await client.allStreams.read { $0.limit = 1000 }.lazy.reduce(0) { count, _ in count + 1 }
    /// ```
    ///
    /// Creating a `ReadCall` performs no network activity. It is deliberately **not** an
    /// `AsyncSequence` in 2.x, and the `read(configure:)` overload that returns it is synchronous
    /// and non-throwing: both are what keeps the existing `try await read()` call sites resolving
    /// to the buffered overload without ambiguity. To hold one in a variable without iterating,
    /// spell the type: `let call: Streams<SpecifiedStream>.ReadCall = stream.read()`.
    ///
    /// The `ReadCall` overload is `@_disfavoredOverload`, so unannotated function references
    /// (`let read = stream.read`) and bare calls keep selecting the buffered `read`; `.lazy` /
    /// `.buffered` chains and an explicit `: ReadCall` annotation select the `ReadCall` overload.
    public struct ReadCall: Sendable {
        let selector: NodeSelector
        let openCall: @Sendable (Node) async throws(KurrentError) -> ScopedCall<ReadResponse>
        let bufferedRead: @Sendable () async throws(KurrentError) -> AsyncThrowingStream<ReadResponse, any Error>

        /// Events delivered as you iterate, with backpressure. Each iteration opens its own RPC.
        public var lazy: Lazy { Lazy(call: self) }

        /// The whole result, fetched before this returns. Identical to `read()`.
        public var buffered: AsyncThrowingStream<ReadResponse, any Error> {
            get async throws(KurrentError) { try await bufferedRead() }
        }
    }
}

extension Streams.ReadCall {
    /// The lazy form of a read: a cold sequence that opens one RPC per iterator.
    ///
    /// The RPC ends when the iterator is released — after the loop finishes, on `break`, on a
    /// thrown error, or when the iterating task is cancelled. Memory is bounded by the hand-off
    /// capacity plus one HTTP/2 stream flow-control window. The only way to keep the RPC open is
    /// to call `makeAsyncIterator()` yourself and hold on to the iterator.
    public struct Lazy: AsyncSequence, Sendable {
        public typealias Element = Streams.ReadResponse
        public typealias Failure = any Error

        let call: Streams.ReadCall

        public func makeAsyncIterator() -> Iterator { Iterator(call: call) }

        public final class Iterator: AsyncIteratorProtocol {
            private let call: Streams.ReadCall
            private var scoped: ScopedCall<Streams.ReadResponse>?
            private var finished = false

            init(call: Streams.ReadCall) { self.call = call }

            deinit {
                // The loop ended without reaching the end (break, throw, cancellation, or the
                // iterator was dropped): end the RPC and return the lease in the background.
                if let scoped, !finished { scoped.closeInBackground() }
            }

            public func next() async throws -> Streams.ReadResponse? {
                if finished { return nil }
                if Task.isCancelled {
                    // Cancelled before the first call or between two: finish for good, and end an
                    // open RPC now instead of at deinit.
                    finished = true
                    if let scoped { await scoped.close() }
                    throw CancellationError()
                }

                let active: ScopedCall<Streams.ReadResponse>
                if let scoped {
                    active = scoped
                } else {
                    // Retry covers only establishing the call: no element has been delivered yet.
                    let call = call   // the retry closures are @Sendable; capture the value, not `self`
                    do {
                        active = try await withRetry(
                            policy: call.selector.retryPolicy,
                            selectNode: { try await call.selector.select() },
                            invalidate: { await call.selector.invalidate() }
                        ) { node in
                            try await call.openCall(node)
                        }
                    } catch {
                        finished = true   // one throw ends the sequence; never reopen on the next call
                        // Node discovery wraps a cancelled task as internalClientError and open()
                        // as connectionClosed; the caller asked to stop either way.
                        if Task.isCancelled { throw CancellationError() }
                        throw error
                    }
                    scoped = active
                }

                do {
                    if let element = try await active.handoff.next() { return element }
                    // Either the server finished the stream or our task was cancelled (the
                    // hand-off ends quietly on consumer-side cancellation).
                    finished = true
                    await active.close()
                    try Task.checkCancellation()
                    return nil
                } catch {
                    finished = true
                    await active.close()
                    throw error
                }
            }
        }
    }
}
