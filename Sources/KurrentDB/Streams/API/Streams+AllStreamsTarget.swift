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
    ///
    /// - Parameter configure: Closure to configure ``ReadAll/Options`` (position, direction, filter, limit). Defaults to no-op.
    /// - Returns: An async throwing stream of `ReadAll.Response` values.
    /// - Throws: `KurrentError` if the read operation fails.
    public func read(configure: @Sendable (inout ReadAll.Options) -> Void = { _ in }) async throws(KurrentError) -> AsyncThrowingStream<ReadAll.Response, Error> {
        var options = ReadAll.Options()
        configure(&options)
        let usecase = ReadAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
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
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
