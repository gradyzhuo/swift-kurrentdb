//
//  Streams+ProjectionStream.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//


/// Operations available on projection streams.
extension Streams where Target == ProjectionStream {
    /// Identifier of the projection stream.
    public var identifier: StreamIdentifier {
        target.identifier
    }

    /// Subscribes to live events from the projection stream.
    ///
    /// - Parameter configure: Closure to configure ``Subscribe/Options`` (starting position). Defaults to no-op.
    /// - Returns: A ``Streams/Subscription`` that delivers events from the projection stream.
    /// - Throws: `KurrentError` if the subscription cannot be established.
    public func subscribe(configure: @Sendable (inout Subscribe.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription {
        var options = Subscribe.Options()
        configure(&options)
        let usecase = Subscribe(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - Multiple Streams Operations

extension Streams where Target == MultiStreamsTarget {
    /// Appends fully-formed stream events across multiple streams in a single session (requires KurrentDB 25.1+).
    ///
    /// - Parameter events: ``StreamEvent`` values to append, each carrying its target stream, event ID, type, and payload.
    /// - Returns: An `AppendSession.Response` with the next expected revisions and server-assigned positions.
    /// - Throws: `KurrentError` if the session fails, a version conflict occurs, or access is denied.
    @discardableResult
    public func append(events: [StreamEvent]) async throws(KurrentError) -> AppendSession.Response {
        let usecase = AppendSession(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Appends a variadic list of fully-formed stream events in a single session (requires KurrentDB 25.1+).
    ///
    /// - Parameter events: One or more ``StreamEvent`` values to append in order.
    /// - Returns: An `AppendSession.Response` with the next expected revisions and server-assigned positions.
    /// - Throws: `KurrentError` if the session fails, a version conflict occurs, or access is denied.
    @discardableResult
    public func append(events: StreamEvent...) async throws(KurrentError) -> AppendSession.Response {
        let usecase = AppendSession(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}