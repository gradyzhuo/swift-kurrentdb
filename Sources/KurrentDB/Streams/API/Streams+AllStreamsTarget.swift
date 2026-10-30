//
//  Streams+AllStreams.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//


// MARK: - All Streams Operations

/// Operations available on the `$all` stream.
extension Streams where Target == AllStreamsTarget {
    /// Reads events lazily: a ``ReadCall`` that opens its RPC when iterated and pulls events as you
    /// iterate, with memory bounded and the RPC ended when the loop ends. Nothing happens until then;
    /// use ``ReadCall/buffered`` to fetch the whole result first.
    ///
    /// Errors arrive during iteration, as described on ``ReadCall/Iterator``. Establishing the call —
    /// node selection to the server's first response — is bounded by
    /// ``ClientSettings/defaultDeadline``; the iteration that follows is not.
    ///
    /// ```swift
    /// for try await response in client.allStreams.read() {
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
            bufferedRead: { () throws(KurrentError) in try await usecase.perform(selector: selector, callOptions: callOptions, credentials: credentials) },
            openParkedCall: { node throws(KurrentError) in try await usecase.openParked(node: node, callOptions: callOptions, credentials: credentials) }
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
