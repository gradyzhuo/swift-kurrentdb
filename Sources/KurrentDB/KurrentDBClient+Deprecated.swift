//
//  KurrentDBClient+Deprecated.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides convenience methods for stream operations.
extension KurrentDBClient {
    /// Appends a batch of events to a specified stream (deprecated).
    ///
    /// - Important: This method has been deprecated. Use `appendToStream(_:events:configure:)` instead.
    ///   The behavior is identical; only the name has changed for clarity.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The unique identifier of the target stream to which the events will be appended.
    ///   - events: An array of `EventData` instances to append in order. The order of events in this
    ///     array is preserved during the append operation.
    ///   - configure: An optional closure that receives the default `Streams<SpecifiedStream>.Append.Options`
    ///     and returns a customized options value. Use this to set expected revision, credentials,
    ///     and other append preferences. Defaults to a no-op that returns the provided options unchanged.
    ///
    /// - Returns: A `Streams<SpecifiedStream>.Append.Response` containing the outcome of the append operation,
    ///   including the next expected revision and any server-assigned positions if available.
    ///
    /// - Throws: An error if the append fails due to revision conflicts, connectivity issues, permission
    ///   errors, or other server-side failures.
    ///
    /// - SeeAlso: ``appendToStream(_:events:configure:)``
    @available(*, deprecated, renamed: "appendToStream")
    public func appendStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await appendToStream(streamIdentifier, events: events, configure: configure)
    }

    /// Appends a batch of events to a stream identified by name (deprecated).
    ///
    /// - Important: This method has been deprecated. Use `appendToStream(_:events:configure:)` instead.
    ///   The behavior is identical; only the name has changed for clarity.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to which the events will be appended.
    ///   - events: An array of `EventData` instances to append in order. The order of events in this
    ///     array is preserved during the append operation.
    ///   - configure: An optional closure that receives the default `Streams<SpecifiedStream>.Append.Options`
    ///     and returns a customized options value. Use this to set expected revision, credentials,
    ///     and other append preferences. Defaults to a no-op that returns the provided options unchanged.
    ///
    /// - Returns: A `Streams<SpecifiedStream>.Append.Response` containing the outcome of the append operation,
    ///   including the next expected revision and any server-assigned positions if available.
    ///
    /// - Throws: An error if the append fails due to revision conflicts, connectivity issues, permission
    ///   errors, or other server-side failures.
    ///
    /// - SeeAlso: ``appendToStream(_:events:configure:)``
    @available(*, deprecated, renamed: "appendToStream")
    @discardableResult
    public func appendStream(_ streamName: String, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await appendToStream(streamName, events: events, configure: configure)
    }

    /// Appends one or more events to a stream identified by name using variadic parameters (deprecated).
    ///
    /// - Important: This method has been deprecated. Use `appendToStream(_:events:configure:)` instead.
    ///   The behavior is identical; only the name has changed for clarity.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to which the events will be appended.
    ///   - events: A variadic list of `EventData` instances to append in order. The order of events
    ///     is preserved during the append operation.
    ///   - configure: An optional closure that receives the default `Streams<SpecifiedStream>.Append.Options`
    ///     and returns a customized options value. Use this to set expected revision, credentials,
    ///     and other append preferences. Defaults to a no-op that returns the provided options unchanged.
    ///
    /// - Returns: A `Streams<SpecifiedStream>.Append.Response` containing the outcome of the append operation,
    ///   including the next expected revision and any server-assigned positions if available.
    ///
    /// - Throws: An error if the append fails due to revision conflicts, connectivity issues, permission
    ///   errors, or other server-side failures.
    ///
    /// - SeeAlso: ``appendToStream(_:events:configure:)``
    @available(*, deprecated, renamed: "appendToStream")
    @discardableResult
    public func appendStream(_ streamName: String, events: EventData..., configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await appendToStream(streamName, events: events, configure: configure)
    }
}
