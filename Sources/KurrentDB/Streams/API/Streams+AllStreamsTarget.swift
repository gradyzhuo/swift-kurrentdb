//
//  Streams+AllStreams.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//


// MARK: - All Streams Operations

/// Operations available on the `$all` stream.
extension Streams where Target == AllStreamsTarget {
    /// Reads events from the `$all` stream.
    /// The whole `$all` result is fetched before this returns, so memory grows with the result; this is the same as ``ReadCall/buffered``. For large reads use `read().lazy`.
    ///
    /// - Parameter configure: Closure to configure ``ReadAll/Options`` (position, direction, filter, limit). Defaults to no-op.
    /// - Returns: An async throwing stream of `ReadAll.Response` values.
    /// - Throws: `KurrentError` if the read operation fails.
    public func read(configure: @Sendable (inout ReadAll.Options) -> Void = { _ in }) async throws(KurrentError) -> AsyncThrowingStream<ReadAll.Response, Error> {
        var options = ReadAll.Options()
        configure(&options)
        let usecase = ReadAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
    }

    /// Prepares a read whose delivery you choose with ``ReadCall/lazy`` or ``ReadCall/buffered``.
    /// Nothing happens until one of them is used.
    ///
    /// Bare `try await read()` calls and function references formed in an async context keep selecting the
    /// buffered overload; a `.lazy` / `.buffered` chain or an explicit `: ReadCall` annotation selects this one,
    /// and so does a function reference formed in a synchronous context, so spell the type if that matters.
    ///
    /// ```swift
    /// for try await response in client.allStreams.read().lazy {
    ///     print(try response.event.record.eventType)
    /// }
    /// ```
    ///
    /// - Parameter configure: Configures ``ReadAll/Options`` (position, direction, filter, limit). Defaults to no-op.
    public func read(configure: @Sendable (inout ReadAll.Options) -> Void = { _ in }) -> ReadCall {
        var options = ReadAll.Options()
        configure(&options)
        let usecase = ReadAll(options: options)
        let selector = selector, callOptions = callOptions, credentials = overrideCredentials
        return ReadCall(
            selector: selector,
            openCall: { node throws(KurrentError) in try await usecase.open(node: node, callOptions: callOptions, credentials: credentials) },
            bufferedRead: { () throws(KurrentError) in try await usecase.perform(selector: selector, callOptions: callOptions, credentials: credentials) }
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
