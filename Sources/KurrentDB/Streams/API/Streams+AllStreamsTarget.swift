//
//  Streams+AllStreams.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//


// MARK: - All Streams Operations

/// Operations available on the `$all` stream.
extension Streams where Target == AllStreamsTarget {
    /// Reads events from the `$all` stream, buffering the whole result.
    ///
    /// Deprecated: the result is fully buffered before this returns; use ``read(configure:isolation:body:)``.
    ///
    /// - Parameter configure: Closure to configure ``ReadAll/Options`` (position, direction, filter, limit). Defaults to no-op.
    /// - Returns: An async throwing stream of `ReadAll.Response` values.
    /// - Throws: `KurrentError` if the read operation fails.
    @available(*, deprecated, message: "Buffers the whole result before returning. Use read(configure:body:): events are delivered to the closure with backpressure and the RPC ends when it returns.")
    public func read(configure: @Sendable (inout ReadAll.Options) -> Void = { _ in }) async throws(KurrentError) -> AsyncThrowingStream<ReadAll.Response, Error> {
        var options = ReadAll.Options()
        configure(&options)
        let usecase = ReadAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
    }

    /// Reads events from `$all` and hands them to `body` as they arrive.
    ///
    /// ```swift
    /// let count = try await client.allStreams.read {
    ///     $0.limit = 10
    /// } body: { events in
    ///     try await events.reduce(0) { total, _ in total + 1 }
    /// }
    /// ```
    ///
    /// Events arrive as `body` consumes them: memory is bounded by the hand-off capacity plus one
    /// HTTP/2 stream flow-control window. When `body` returns or throws, the RPC has ended and
    /// its connection lease is released. The stream is valid only inside `body`; iterated after
    /// `read` returned, it ends at once. Errors thrown by `body` are rethrown unchanged.
    ///
    /// A call the server rejects before accepting it (a status-only response such as
    /// unauthenticated, access denied or unavailable), or a connection failure, is thrown before
    /// `body` runs as `KurrentError`; node failures among them are retried per the client's retry
    /// policy. Errors after
    /// the call was accepted, including stream-not-found (which arrives as a response message),
    /// surface while `body` iterates.
    ///
    /// If the caller's task is cancelled, `read` throws `CancellationError` at whatever stage the
    /// cancellation lands (node selection, waiting for the server to accept the call, or after
    /// `body` started); `body` sees the stream end and its result is discarded.
    ///
    /// A `body` that stops iterating keeps the RPC open until it returns; the server stops
    /// sending once the buffers are full.
    ///
    /// - Parameters:
    ///   - configure: Configures ``ReadAll/Options`` (position, direction, filter, limit). Defaults to no-op.
    ///   - body: Consumes the events. Its return value is returned by `read`.
    public func read<R>(
        configure: @Sendable (inout ReadAll.Options) -> Void = { _ in },
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<ReadAll.Response, any Error>) async throws -> sending R
    ) async throws -> R {
        var options = ReadAll.Options()
        configure(&options)
        let usecase = ReadAll(options: options)
        return try await usecase.performScoped(
            selector: selector,
            callOptions: callOptions,
            credentials: overrideCredentials,
            isolation: isolation,
            body: body
        )
    }

    /// Subscribes to live events from the `$all` stream.
    ///
    /// - Parameter configure: Closure to configure ``SubscribeAll/Options`` (starting position, filter). Defaults to no-op.
    /// - Returns: A ``Streams/Subscription`` that delivers events as they are committed.
    /// - Throws: `KurrentError` if the subscription cannot be established.
    public func subscribe(configure: @Sendable (inout SubscribeAll.Options) -> Void = { _ in }) async throws(KurrentError) -> Streams.Subscription {
        var options = SubscribeAll.Options()
        configure(&options)
        let usecase = SubscribeAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
    }
}
