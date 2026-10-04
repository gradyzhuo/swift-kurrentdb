//
//  Streams+ScopedDelivery.swift
//  KurrentStreams
//

extension Streams where Target: SpecifiedStreamTarget {
    /// Returns an interface whose reads deliver events to a closure with backpressure.
    ///
    /// ```swift
    /// let total = try await client.streams(specified: "orders")
    ///     .delivery(.scoped)
    ///     .read { events in
    ///         try await events.reduce(0) { count, _ in count + 1 }
    ///     }
    /// ```
    ///
    /// - Parameter delivery: `.scoped`.
    /// - Returns: A ``ScopedStreams`` bound to the same target, credentials and call options.
    public func delivery(_ delivery: ScopedDelivery) -> ScopedStreams<Target> {
        ScopedStreams(base: self)
    }
}

extension Streams where Target == AllStreamsTarget {
    /// Returns an interface whose reads deliver events to a closure with backpressure.
    ///
    /// ```swift
    /// let total = try await client.streams(specified: "orders")
    ///     .delivery(.scoped)
    ///     .read { events in
    ///         try await events.reduce(0) { count, _ in count + 1 }
    ///     }
    /// ```
    ///
    /// - Parameter delivery: `.scoped`.
    /// - Returns: A ``ScopedStreams`` bound to the same target, credentials and call options.
    public func delivery(_ delivery: ScopedDelivery) -> ScopedStreams<Target> {
        ScopedStreams(base: self)
    }
}

/// Stream reads with scoped delivery: memory stays bounded while events are consumed, and
/// when `body` returns or throws the RPC has ended and its connection lease is returned.
///
/// Only `read` is scoped; use the `Streams` instance for every other operation.
public struct ScopedStreams<Target: StreamsTarget>: Sendable {
    let base: Streams<Target>

    /// Returns a copy that sends `credentials` with its reads instead of the client's default.
    public func authenticated(_ credentials: Authentication) -> ScopedStreams<Target> {
        ScopedStreams(base: base.authenticated(credentials))
    }
}

extension ScopedStreams where Target: SpecifiedStreamTarget {
    /// Reads events from the stream and hands them to `body` as they arrive.
    ///
    /// ```swift
    /// try await client.streams(specified: "orders")
    ///     .delivery(.scoped)
    ///     .read {
    ///         $0.limit = 100
    ///     } body: { events in
    ///         for try await response in events {
    ///             print(try response.event.record.eventType)
    ///         }
    ///     }
    /// ```
    ///
    /// The stream is valid only inside `body`; iterated after `read` returned, it ends at once.
    ///
    /// A call the server rejects before accepting it (a status-only response such as
    /// unauthenticated, access denied or unavailable), or a connection failure, is thrown by
    /// `read(...)` before `body` runs, as `KurrentError`, and is retried per the client's retry
    /// policy. Errors after the call was accepted, including stream-not-found (which arrives as
    /// a response message), surface while `body` iterates, as with `read()`. Errors thrown by
    /// `body` itself are rethrown unchanged.
    ///
    /// If the caller's task is cancelled, `read` throws `CancellationError` (whether while
    /// waiting for the server to accept the call or after `body` started); `body` sees the
    /// stream end and its result is discarded.
    ///
    /// A `body` that stops iterating keeps the RPC open until it returns; meanwhile buffered
    /// memory is bounded by the hand-off capacity plus one HTTP/2 stream flow-control window,
    /// after which the server stops sending.
    ///
    /// - Parameters:
    ///   - configure: Configures ``Streams/Read/Options`` (direction, limit, starting revision).
    ///   - body: Consumes the events. Its return value is returned by `read`.
    public func read<R>(
        configure: @Sendable (inout Streams<Target>.Read.Options) -> Void = { _ in },
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<Streams<Target>.Read.Response, any Error>) async throws -> sending R
    ) async throws -> R {
        var options = Streams<Target>.Read.Options()
        configure(&options)
        let usecase = Streams<Target>.Read(from: base.identifier, options: options)
        return try await usecase.performScoped(
            selector: base.selector,
            callOptions: base.callOptions,
            credentials: base.overrideCredentials,
            isolation: isolation,
            body: body
        )
    }
}

extension ScopedStreams where Target == AllStreamsTarget {
    /// Reads events from `$all` and hands them to `body` as they arrive.
    ///
    /// ```swift
    /// let count = try await client.allStreams
    ///     .delivery(.scoped)
    ///     .read {
    ///         $0.limit = 10
    ///     } body: { events in
    ///         try await events.reduce(0) { total, _ in total + 1 }
    ///     }
    /// ```
    ///
    /// The stream is valid only inside `body`; iterated after `read` returned, it ends at once.
    ///
    /// A call the server rejects before accepting it (a status-only response such as
    /// unauthenticated, access denied or unavailable), or a connection failure, is thrown by
    /// `read(...)` before `body` runs, as `KurrentError`, and is retried per the client's retry
    /// policy. Errors after the call was accepted, including stream-not-found (which arrives as
    /// a response message), surface while `body` iterates, as with `read()`. Errors thrown by
    /// `body` itself are rethrown unchanged.
    ///
    /// If the caller's task is cancelled, `read` throws `CancellationError` (whether while
    /// waiting for the server to accept the call or after `body` started); `body` sees the
    /// stream end and its result is discarded.
    ///
    /// A `body` that stops iterating keeps the RPC open until it returns; meanwhile buffered
    /// memory is bounded by the hand-off capacity plus one HTTP/2 stream flow-control window,
    /// after which the server stops sending.
    ///
    /// - Parameters:
    ///   - configure: Configures ``Streams/ReadAll/Options`` (position, direction, filter, limit).
    ///   - body: Consumes the events. Its return value is returned by `read`.
    public func read<R>(
        configure: @Sendable (inout Streams<AllStreamsTarget>.ReadAll.Options) -> Void = { _ in },
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<Streams<AllStreamsTarget>.ReadAll.Response, any Error>) async throws -> sending R
    ) async throws -> R {
        var options = Streams<AllStreamsTarget>.ReadAll.Options()
        configure(&options)
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: options)
        return try await usecase.performScoped(
            selector: base.selector,
            callOptions: base.callOptions,
            credentials: base.overrideCredentials,
            isolation: isolation,
            body: body
        )
    }
}
