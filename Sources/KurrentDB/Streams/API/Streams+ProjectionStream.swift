//
//  Streams+ProjectionStream.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//


/// Provides operations for projection streams.
extension Streams where Target == ProjectionStream {
    /// The identifier of the projection stream.
    public var identifier: StreamIdentifier {
        target.identifier
    }

    /// Subscribes to events from the specified projection stream.
    ///
    /// - Parameter configure: A closure to configure subscription options. Defaults to no-op.
    /// - Returns: A subscription that receives events from the stream.
    /// - Throws: `KurrentError` if the subscription cannot be established.
    public func subscribe(configure: @Sendable (inout Subscribe.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription {
        var options = Subscribe.Options()
        configure(&options)
        let usecase = Subscribe(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - Multiple Streams Operations

extension Streams where Target == MultiStreams {
    /// Appends a batch of pre-constructed stream events using an append session. (KurrentDB > 25.1)
    ///
    /// Use this when you already have fully-formed `StreamEvent` values (including
    /// their event IDs, types, content type, and data) and want to persist them in
    /// a single session. This is useful for advanced scenarios like idempotent
    /// writes, preserving event IDs across retries, or when events are built
    /// incrementally by upstream systems.
    ///
    /// - Parameter events: The collection of `StreamEvent` values to append in order.
    /// - Returns: An `AppendSession.Response` describing the outcome of the session,
    ///   including the next expected revision and any server-assigned positions.
    /// - Throws: `KurrentError` if the session could not be established or the write
    ///   fails, for example due to version conflicts, access issues, or transport errors.
    @discardableResult
    public func append(events: [StreamEvent]) async throws(KurrentError) -> AppendSession.Response {
        let usecase = AppendSession(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Appends a variadic list of pre-constructed stream events in a single append session.  (KurrentDB > 25.1)
    ///
    /// Use this when you already have fully formed `StreamEvent` values (including IDs,
    /// types, content type, and payload) and want to persist them together while preserving
    /// ordering and event IDs. This is useful for idempotent writes, retries, or when events
    /// are assembled upstream.
    ///
    /// - Parameter events: One or more `StreamEvent` values to append in order.
    /// - Returns: An `AppendSession.Response` describing the outcome, including the next
    ///   expected revision and any server-assigned positions.
    /// - Throws: `KurrentError` if the session cannot be established or the write fails
    ///   (e.g., due to version conflicts, access issues, or transport errors).
    /// - Note: Events are appended in the order provided and are not transformed; ensure
    ///   each `StreamEvent` carries the desired identifiers and content metadata.
    @discardableResult
    public func append(events: StreamEvent...) async throws(KurrentError) -> AppendSession.Response {
        let usecase = AppendSession(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}