//
//  KurrentDBClient+Streams.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides convenience methods for stream operations.
extension KurrentDBClient {
    /// Sets the metadata for the specified stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to set metadata for.
    ///   - metadata: The metadata to set for the stream.
    ///   - expectedRevision: The expected revision of the stream. Defaults to `.any`.
    /// - Returns: The response from appending the metadata to the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func setStreamMetadata(_ streamIdentifier: StreamIdentifier, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamIdentifier)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves the metadata for the specified stream using the stream identifier.
    ///
    /// - Parameter streamIdentifier: The identifier of the stream to get metadata for.
    /// - Returns: The metadata of the stream, or `nil` if not found.
    /// - Throws: An error if the operation fails.
    public func getStreamMetadata(_ streamIdentifier: StreamIdentifier) async throws -> StreamMetadata? {
        try await streams(of: .specified(streamIdentifier)).getMetadata()
    }

    
    /// Appends one or more events to a specific stream.
    ///
    /// Use this method to optimistically append a batch of `EventData` to a stream
    /// identified by `streamIdentifier`. You can customize concurrency expectations,
    /// credentials, and other append behaviors by providing a configuration closure
    /// that modifies `Streams<SpecifiedStream>.Append.Options`.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The unique identifier of the target stream to which the events will be appended.
    ///   - events: An ordered array of `EventData` to append. The order provided is preserved by the append operation.
    ///   - configure: An optional closure that receives the default `Streams<SpecifiedStream>.Append.Options`
    ///     and returns a customized options value (for example, to set the expected revision, credentials,
    ///     or deadline). Defaults to a no-op that returns the provided options unchanged.
    /// - Returns: A `Streams<SpecifiedStream>.Append.Response` describing the result of the append,
    ///   including the next expected revision and, when available, the server-assigned log position.
    /// - Throws: An error if the append fails due to revision conflicts (e.g., optimistic concurrency),
    ///   permission issues, connectivity problems, or other server-side errors.
    /// - Note: This method is `async` and may suspend while communicating with the server. Use `await`
    ///   from an asynchronous context. Consider setting an expected revision in the options to enforce
    ///   optimistic concurrency if multiple writers may target the same stream.
    /// - SeeAlso: `Streams<SpecifiedStream>.Append.Options`, `Streams<SpecifiedStream>.Append.Response`
    @discardableResult
    public func appendToStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }
    
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
    public func appendStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response{
        return try await appendToStream(streamIdentifier, events: events, configure: configure)
    }
    
    
    /// Appends multiple events to their respective streams in a single batch operation. (KurrentDB > 25.1)
    ///
    /// This convenience method targets the `$all` stream context and appends a collection
    /// of stream-scoped events. Each `StreamEvent` encapsulates both the destination
    /// stream and the event payload, allowing you to efficiently write to many streams
    /// within one append session.
    ///
    /// - Parameter streamEvents: An array of `StreamEvent` values, where each item
    ///   specifies the target stream and the event data to append.
    /// - Returns: A `Streams<AllStreams>.AppendSession.Response` describing the outcome
    ///   of the batch append, including per-event results where applicable.
    /// - Throws: An error if the append session fails to start, any event fails to be
    ///   appended, or if the server returns an error during the operation.
    /// - Note: Ordering and atomicity guarantees depend on the server’s implementation
    ///   of batch append sessions for the `$all` stream. Check server-side configuration
    ///   and documentation for transactional behavior and concurrency semantics.
    @discardableResult
    public func appendToStreams(_ streamEvents: [StreamEvent]) async throws -> Streams<MultiStreams>.AppendSession.Response {
        return try await streams(of: .multiple).append(events: streamEvents)
    }

    /// Reads all events from the `$all` stream starting from the specified position.
    ///
    /// - Parameter configure: A closure to configure the read options. Defaults to no configuration.
    /// - Returns: The responses containing the read events.
    /// - Throws: An error if the operation fails.
    public func readAllStreams(configure: @Sendable (Streams<AllStreams>.ReadAll.Options) -> Streams<AllStreams>.ReadAll.Options = { $0 }) async throws -> Streams<AllStreams>.ReadAll.Responses {
        let options = configure(.init())
        return try await streams(of: .all).read(options: options)
    }

    /// Reads all events from the specified stream, optionally starting from a specific revision.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to read events from.
    ///   - configure: A closure to configure the read options. Defaults to no configuration.
    /// - Returns: The responses containing the read events.
    /// - Throws: An error if the operation fails.
    public func readStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).read(options: options)
    }

    /// Subscribes to events from the `$all` stream starting from the specified position.
    ///
    /// - Parameter configure: A closure to configure the subscription options. Defaults to no configuration.
    /// - Returns: The subscription to the `$all` stream.
    /// - Throws: An error if the operation fails.
    public func subscribeAllStreams(configure: @Sendable (Streams<AllStreams>.SubscribeAll.Options) -> Streams<AllStreams>.SubscribeAll.Options = { $0 }) async throws -> Streams<AllStreams>.Subscription {
        let options = configure(.init())
        return try await streams(of: .all).subscribe(options: options)
    }

    /// Subscribes to events from the specified stream, optionally starting from a specific revision.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to subscribe to.
    ///   - configure: A closure to configure the subscription options. Defaults to no configuration.
    /// - Returns: The subscription to the specified stream.
    /// - Throws: An error if the operation fails.
    public func subscribeStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).subscribe(options: options)
    }

    /// Soft deletes the specified stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to delete.
    ///   - configure: A closure to configure the delete options. Defaults to no configuration.
    /// - Returns: The response from deleting the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func deleteStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).delete(options: options)
    }

    /// Hard deletes (tombstones) the specified stream, making the stream identifier unusable.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to tombstone.
    ///   - configure: A closure to configure the tombstone options. Defaults to no configuration.
    /// - Returns: The response from tombstoning the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func tombstoneStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).tombstone(options: options)
    }

    /// Sets the metadata for the specified stream using the stream name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to set metadata for.
    ///   - metadata: The metadata to set for the stream.
    ///   - expectedRevision: The expected revision of the stream. Defaults to `.any`.
    /// - Returns: The response from appending the metadata to the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func setStreamMetadata(_ streamName: String, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamName)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves the metadata for the specified stream using the stream name.
    ///
    /// - Parameter streamName: The name of the stream to get metadata for.
    /// - Returns: The metadata of the stream, or `nil` if not found.
    /// - Throws: An error if the operation fails.
    public func getStreamMetadata(_ streamName: String) async throws -> StreamMetadata? {
        try await streams(of: .specified(streamName)).getMetadata()
    }

    /// Appends events to the specified stream using the stream name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to append events to.
    ///   - events: The events to append to the stream.
    ///   - configure: A closure to configure the append options. Defaults to no configuration.
    /// - Returns: The response from appending the events to the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func appendStream(_ streamName: String, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    /// Appends events to the specified stream using the stream name, with variadic event input.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to append events to.
    ///   - events: The events to append to the stream, passed as variadic parameters.
    ///   - configure: A closure to configure the append options. Defaults to no configuration.
    /// - Returns: The response from appending the events to the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func appendStream(_ streamName: String, events: EventData..., configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    /// Reads all events from the specified stream, optionally starting from a specific revision, using the stream name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to read events from.
    ///   - configure: A closure to configure the read options. Defaults to no configuration.
    /// - Returns: The responses containing the read events.
    /// - Throws: An error if the operation fails.
    public func readStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).read(options: options)
    }

    /// Subscribes to events from the specified stream, optionally starting from a specific revision, using the stream name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to subscribe to.
    ///   - configure: A closure to configure the subscription options. Defaults to no configuration.
    /// - Returns: The subscription to the specified stream.
    /// - Throws: An error if the operation fails.
    public func subscribeStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).subscribe(options: options)
    }

    /// Soft deletes the specified stream using the stream name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to delete.
    ///   - configure: A closure to configure the delete options. Defaults to no configuration.
    /// - Returns: The response from deleting the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func deleteStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).delete(options: options)
    }

    /// Hard deletes (tombstones) the specified stream, making the stream identifier unusable, using the stream name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to tombstone.
    ///   - configure: A closure to configure the tombstone options. Defaults to no configuration.
    /// - Returns: The response from tombstoning the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func tombstoneStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).tombstone(options: options)
    }
}


extension KurrentDBClient {
    
    public func listStreams(category: String?){
        streams(of: .specified("$"))
    }
    
}
