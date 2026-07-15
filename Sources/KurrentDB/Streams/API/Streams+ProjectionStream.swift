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
        return try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
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
        return try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
    }

    /// Appends a variadic list of fully-formed stream events in a single session (requires KurrentDB 25.1+).
    ///
    /// - Parameter events: One or more ``StreamEvent`` values to append in order.
    /// - Returns: An `AppendSession.Response` with the next expected revisions and server-assigned positions.
    /// - Throws: `KurrentError` if the session fails, a version conflict occurs, or access is denied.
    @discardableResult
    public func append(events: StreamEvent...) async throws(KurrentError) -> AppendSession.Response {
        let usecase = AppendSession(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
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

    /// Pipelines multiple appends over a single `BatchAppend` call for high throughput (requires a
    /// server that supports BatchAppend).
    ///
    /// Unlike ``append(events:)-(_)`` (AppendSession, atomic), this is **non-atomic**: each
    /// ``StreamEvent`` is an independent append, so some may succeed while others fail. Inspect the
    /// returned ``BatchAppend/Response`` (`results` / `failed`) instead of relying on a thrown error
    /// for per-item conflicts. Only transport-level failures are thrown.
    ///
    /// - Parameter events: Append operations to pipeline, each with its own stream and expected revision.
    /// - Returns: A ``BatchAppend/Response`` with a per-item result in input order.
    /// - Throws: `KurrentError` on transport failure, access denial, or when the server does not
    ///   support BatchAppend.
    @discardableResult
    public func batchAppend(events: [StreamEvent]) async throws(KurrentError) -> BatchAppend.Response {
        let usecase = BatchAppend(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Pipelines a variadic list of appends over a single `BatchAppend` call (non-atomic).
    ///
    /// - Parameter events: One or more append operations to pipeline.
    /// - Returns: A ``BatchAppend/Response`` with a per-item result in input order.
    /// - Throws: `KurrentError` on transport failure, access denial, or unsupported server.
    @discardableResult
    public func batchAppend(events: StreamEvent...) async throws(KurrentError) -> BatchAppend.Response {
        let usecase = BatchAppend(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}