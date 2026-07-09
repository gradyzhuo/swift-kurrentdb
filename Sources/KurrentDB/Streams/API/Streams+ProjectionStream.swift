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

    /// Appends records across one or more streams atomically with cross-stream consistency checks
    /// (Dynamic Consistency Boundary). Requires KurrentDB 25.1+.
    ///
    /// Each ``StreamEvent`` whose `expectedRevision` is not `.any` becomes an implicit check on its
    /// own stream. Additional ``checks`` may reference **any** stream — including streams this call
    /// does not write to — so a decision can depend on multiple streams while producing events for
    /// only a subset.
    ///
    /// - Parameters:
    ///   - events: ``StreamEvent`` values to append, each carrying its target stream and records.
    ///   - checks: Extra pre-commit consistency checks on any stream. Defaults to none.
    /// - Returns: An ``AppendRecords/Response`` with per-stream revisions and the commit position.
    /// - Throws: ``KurrentError/consistencyViolation(violations:)`` if any check fails (reporting all
    ///   failing checks at once); other `KurrentError` cases on transport or access failures.
    @discardableResult
    public func appendRecords(events: [StreamEvent], checks: [ConsistencyCheck] = []) async throws(KurrentError) -> AppendRecords.Response {
        let usecase = AppendRecords(streamEvents: events, checks: checks)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Appends a variadic list of records across one or more streams atomically with cross-stream
    /// consistency checks (Dynamic Consistency Boundary). Requires KurrentDB 25.1+.
    ///
    /// - Parameters:
    ///   - events: One or more ``StreamEvent`` values to append, in order.
    ///   - checks: Extra pre-commit consistency checks on any stream. Defaults to none.
    /// - Returns: An ``AppendRecords/Response`` with per-stream revisions and the commit position.
    /// - Throws: ``KurrentError/consistencyViolation(violations:)`` if any check fails; other
    ///   `KurrentError` cases on transport or access failures.
    @discardableResult
    public func appendRecords(events: StreamEvent..., checks: [ConsistencyCheck] = []) async throws(KurrentError) -> AppendRecords.Response {
        let usecase = AppendRecords(streamEvents: events, checks: checks)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}