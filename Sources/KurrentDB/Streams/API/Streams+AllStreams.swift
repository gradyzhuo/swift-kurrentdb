//
//  Streams+AllStreams.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//


// MARK: - All Streams Operations

/// Provides operations for all streams.
extension Streams where Target == AllStreams {
    /// Reads events from all available streams.
    ///
    /// - Parameter configure: A closure to configure the read operation, such as filters or limits. Defaults to no-op.
    /// - Returns: An asynchronous throwing stream of read responses containing events from all streams.
    /// - Throws: `KurrentError` if the read operation fails.
    public func read(configure: @Sendable (inout ReadAll.Options) -> Void = { _ in }) async throws(KurrentError) -> AsyncThrowingStream<ReadAll.Response, Error> {
        var options = ReadAll.Options()
        configure(&options)
        let usecase = ReadAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Subscribes to all event streams, delivering events as they occur.
    ///
    /// - Parameter configure: A closure to configure subscription options, including filters and starting position. Defaults to no-op.
    /// - Returns: A subscription that receives events from all streams.
    /// - Throws: `KurrentError` if the subscription fails.
    public func subscribe(configure: @Sendable (inout SubscribeAll.Options) -> Void = { _ in }) async throws(KurrentError) -> Streams.Subscription {
        var options = SubscribeAll.Options()
        configure(&options)
        let usecase = SubscribeAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
