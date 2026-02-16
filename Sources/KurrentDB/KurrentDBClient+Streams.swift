//
//  KurrentDBClient+Streams.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

extension KurrentDBClient {
    /// Creates a type-safe streams interface for the specified target.
    ///
    /// This method returns a `Streams` instance configured for operations on a specific
    /// stream, the `$all` stream, or multiple streams simultaneously. The returned instance
    /// inherits the client's node selector, call options, and event loop group for consistent
    /// behavior across all stream operations.
    ///
    /// ## Target Types
    ///
    /// - `SpecifiedStream`: Operations on a single named stream
    /// - `AllStreams`: Operations on the `$all` stream (global event log)
    /// - `MultiStreams`: Batch operations across multiple streams
    /// - `ProjectionStream`: Operations on projection-generated streams
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Access a specific stream
    /// let ordersStream = client.streams(of: .specified("orders"))
    /// try await ordersStream.append(events: events)
    ///
    /// // Access the $all stream
    /// let allStream = client.streams(of: .all)
    /// let events = try await allStream.read()
    /// ```
    ///
    /// - Parameter target: The stream target defining the scope of operations. Use static
    ///   factory methods like `.specified(_:)`, `.all`, or `.multiple` to create targets.
    ///
    /// - Returns: A configured `Streams<Target>` instance ready for stream operations.
    ///
    /// - Note: This method creates a new streams instance on each call. For repeated operations
    ///   on the same stream, consider storing the returned instance to avoid recreation overhead.
    ///
    /// - SeeAlso: `StreamsTarget`, `Streams`, `SpecifiedStream`, `AllStreams`
    public func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}

extension KurrentDBClient {
    /// Creates a streams interface for a specific stream by name.
    ///
    /// This convenience method is equivalent to calling `streams(of: .specified(name))` but
    /// provides a more concise syntax for the common case of accessing a single stream.
    ///
    /// - Parameter name: The name of the stream to access.
    ///
    /// - Returns: A `Streams<SpecifiedStream>` instance configured for the named stream.
    ///
    /// - SeeAlso: `streams(of:)`, `SpecifiedStream`
    public func streams(specified name: String) -> Streams<SpecifiedStream> {
        streams(of: .specified(name))
    }

    /// Accesses the multi-streams interface for batch operations across multiple streams.
    ///
    /// The multi-streams interface enables efficient batch operations that span multiple
    /// streams, such as the append session API introduced in KurrentDB 25.1+. This is
    /// particularly useful for scenarios requiring transactional writes across streams
    /// or bulk data ingestion.
    ///
    /// - Returns: A `Streams<MultiStreams>` instance for multi-stream operations.
    ///
    /// - Note: Multi-stream operations require KurrentDB server version 25.1 or later.
    ///
    /// - SeeAlso: `appendToStreams(events:)`, `MultiStreams`
    public var multiStreams: Streams<MultiStreams> {
        streams(of: .multiple)
    }

    /// Accesses the `$all` stream for global event log operations.
    ///
    /// The `$all` stream provides access to the global event log containing every event
    /// written to the database across all streams. This is useful for implementing catch-up
    /// subscriptions, building read models that aggregate data from multiple streams, or
    /// performing global event processing.
    ///
    /// ## Common Use Cases
    ///
    /// - Catch-up subscriptions that process all events
    /// - Cross-stream event aggregation
    /// - Event replay for audit or recovery
    /// - Global event monitoring and analytics
    ///
    /// - Returns: A `Streams<AllStreams>` instance for `$all` stream operations.
    ///
    /// - Warning: Reading from `$all` can return a very large number of events. Always
    ///   use appropriate filtering and pagination when working with the global log.
    ///
    /// - SeeAlso: `readAllStreams(configure:)`, `subscribeAllStreams(configure:)`
    public var allStreams: Streams<AllStreams> {
        streams(of: .all)
    }
}

// MARK: - Stream Metadata Operations

extension KurrentDBClient {
    /// Sets metadata for a stream identified by its StreamIdentifier.
    ///
    /// Stream metadata controls various aspects of stream behavior, including ACLs,
    /// maximum age, maximum count, truncation policies, and caching strategies. This
    /// operation writes metadata to a special `$$stream-name` system stream.
    ///
    /// ## Metadata Properties
    ///
    /// Common metadata configurations include:
    /// - `maxAge`: Maximum age of events before automatic deletion
    /// - `maxCount`: Maximum number of events to retain
    /// - `truncateBefore`: Event number below which to truncate
    /// - `cacheControl`: Client-side caching behavior
    /// - `acl`: Access control lists for read/write permissions
    ///
    /// ## Example
    ///
    /// ```swift
    /// let metadata = StreamMetadata(
    ///     maxCount: 1000,
    ///     maxAge: TimeSpan(days: 7)
    /// )
    /// try await client.setStreamMetadata(
    ///     .init(name: "orders"),
    ///     metadata: metadata,
    ///     expectedRevision: .any
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to set metadata for.
    ///   - metadata: The metadata configuration to apply.
    ///   - expectedRevision: The expected revision for optimistic concurrency control.
    ///     Use `.any` to skip revision checks, or provide a specific revision to ensure
    ///     no concurrent modifications have occurred. Defaults to `.any`.
    ///
    /// - Returns: The append response containing the new revision number.
    ///
    /// - Throws: `KurrentError` if the operation fails due to revision mismatch, permission
    ///   denial, or network errors.
    ///
    /// - SeeAlso: `StreamMetadata`, `StreamRevision`, `getStreamMetadata(_:)`
    @discardableResult
    public func setStreamMetadata(_ streamIdentifier: StreamIdentifier, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamIdentifier)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves metadata for a stream identified by its StreamIdentifier.
    ///
    /// Reads the current metadata configuration from the stream's associated metadata stream
    /// (`$$stream-name`). Returns `nil` if no metadata has been explicitly set for the stream,
    /// meaning the stream uses default system settings.
    ///
    /// - Parameter streamIdentifier: The identifier of the stream to retrieve metadata for.
    ///
    /// - Returns: The stream's metadata configuration, or `nil` if no custom metadata exists.
    ///
    /// - Throws: `KurrentError` if the operation fails due to permission denial, stream not
    ///   found, or network errors.
    ///
    /// - SeeAlso: `StreamMetadata`, `setStreamMetadata(_:metadata:expectedRevision:)`
    public func getStreamMetadata(_ streamIdentifier: StreamIdentifier) async throws -> StreamMetadata? {
        try await streams(of: .specified(streamIdentifier)).getMetadata()
    }
}

// MARK: - Stream Append Operations

extension KurrentDBClient {
    /// Appends events to a stream identified by its StreamIdentifier.
    ///
    /// This is the primary method for writing events to KurrentDB. Events are written atomically
    /// as a batch - either all events succeed or all fail. The operation supports optimistic
    /// concurrency control through expected revisions to prevent lost updates.
    ///
    /// ## Optimistic Concurrency
    ///
    /// Use the `configure` closure to set the expected revision:
    /// - `.any`: Accept any stream state (no concurrency check)
    /// - `.noStream`: Expect stream does not exist (create new)
    /// - `.streamExists`: Expect stream exists (append to existing)
    /// - `.revision(n)`: Expect stream to be at exactly revision n
    ///
    /// ## Example
    ///
    /// ```swift
    /// let events = [
    ///     EventData(eventType: "OrderCreated", model: ["orderId": "123"]),
    ///     EventData(eventType: "ItemAdded", model: ["itemId": "456"])
    /// ]
    ///
    /// let response = try await client.appendToStream(
    ///     .init(name: "order-123"),
    ///     events: events
    /// ) {
    ///     $0.revision(expected: .noStream)  // Ensure this is a new stream
    /// }
    ///
    /// print("Appended at revision: \(response.nextExpectedRevision)")
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - events: An array of events to append. Events are written in the order provided.
    ///   - configure: A closure to configure append options, including expected revision,
    ///     credentials, and timeouts. Defaults to no configuration (`.any` revision).
    ///
    /// - Returns: An append response containing the next expected revision and log position.
    ///
    /// - Throws: `KurrentError` with specific cases:
    ///   - `.wrongExpectedVersion`: Expected revision does not match actual stream state
    ///   - `.accessDenied`: Insufficient permissions to write to the stream
    ///   - `.streamDeleted`: Attempting to write to a deleted stream
    ///   - `.networkError`: Connection or communication failure
    ///
    /// - Note: Empty event arrays are valid and will succeed without writing any events.
    ///
    /// - SeeAlso: `EventData`, `StreamRevision`, `Streams.Append.Options`
    @discardableResult
    public func appendToStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }

    /// Appends events to multiple streams in a single batch operation.
    ///
    /// This method uses the KurrentDB v2 append session API to write events to multiple streams
    /// efficiently. Each `StreamEvent` encapsulates the target stream, events, and expected
    /// revision, allowing fine-grained control over multi-stream writes.
    ///
    /// ## Requirements
    ///
    /// - Requires KurrentDB server version 25.1 or later
    /// - Server must have the v2 gRPC endpoint enabled
    ///
    /// ## Use Cases
    ///
    /// - Bulk data ingestion across multiple streams
    /// - Event-driven sagas requiring writes to multiple aggregates
    /// - Data migration or replay scenarios
    /// - Cross-stream transactional patterns
    ///
    /// ## Example
    ///
    /// ```swift
    /// let events = [
    ///     StreamEvent(
    ///         streamIdentifier: .init(name: "orders"),
    ///         records: [orderCreatedEvent],
    ///         expectedRevision: .noStream
    ///     ),
    ///     StreamEvent(
    ///         streamIdentifier: .init(name: "inventory"),
    ///         records: [inventoryDeductedEvent],
    ///         expectedRevision: .streamExists
    ///     )
    /// ]
    ///
    /// try await client.appendToStreams(events: events)
    /// ```
    ///
    /// - Parameter events: An array of `StreamEvent` objects, each defining a target stream
    ///   and its events to append.
    ///
    /// - Returns: An append session response containing results for each stream.
    ///
    /// - Throws: `KurrentError` with specific cases:
    ///   - `.unsupportedFeature`: Server version does not support append sessions
    ///   - `.wrongExpectedVersion`: One or more streams have revision mismatches
    ///   - `.networkError`: Connection failure during the operation
    ///
    /// - Important: While events are sent in a single session, KurrentDB does not guarantee
    ///   atomic writes across multiple streams. Each stream is written independently.
    ///
    /// - SeeAlso: `StreamEvent`, `EventRecord`, `MultiStreams`
    @discardableResult
    public func appendToStreams(events: [StreamEvent]) async throws -> Streams<MultiStreams>.AppendSession.Response {
        try await streams(of: .multiple).append(events: events)
    }
}

// MARK: - Stream Read Operations

extension KurrentDBClient {
    /// Reads events from the `$all` stream (global event log).
    ///
    /// The `$all` stream contains every event written to the database across all streams,
    /// ordered by commit position. This method returns an async throwing stream that yields
    /// events as they are read from the server.
    ///
    /// ## Configuration Options
    ///
    /// Use the `configure` closure to set:
    /// - Start position: `.start`, `.end`, or specific commit position
    /// - Read direction: forward or backward
    /// - Event count limit
    /// - Event filters (by event type or stream name)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let events = try await client.readAllStreams { options in
    ///     options
    ///         .startFrom(position: .start)
    ///         .forward()
    ///         .limit(100)
    ///         .filterBy(eventTypes: ["OrderCreated", "OrderUpdated"])
    /// }
    ///
    /// for try await response in events {
    ///     if case .event(let event) = response {
    ///         print("Event: \(event.event.eventType)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter configure: A closure to configure read options. Defaults to reading forward
    ///   from the beginning with no limit.
    ///
    /// - Returns: An async throwing stream of read responses containing events and metadata.
    ///
    /// - Throws: `KurrentError` if the operation fails due to permission denial or network errors.
    ///
    /// - Warning: Reading the entire `$all` stream without limits can return millions of events.
    ///   Always use filtering and pagination for production use.
    ///
    /// - SeeAlso: `Streams.ReadAll.Options`, `ReadEvent`, `StreamPosition`
    public func readAllStreams(configure: @Sendable (Streams<AllStreams>.ReadAll.Options) -> Streams<AllStreams>.ReadAll.Options = { $0 }) async throws -> Streams<AllStreams>.ReadAll.Responses {
        let options = configure(.init())
        return try await streams(of: .all).read(options: options)
    }

    /// Reads events from a specific stream.
    ///
    /// Returns an async throwing stream that yields events from the specified stream.
    /// Events are returned in the order they were written (by revision number), and
    /// the stream can be read either forward or backward from any revision.
    ///
    /// ## Configuration Options
    ///
    /// Use the `configure` closure to set:
    /// - Start revision: `.start`, `.end`, or specific revision number
    /// - Read direction: forward or backward
    /// - Event count limit
    /// - Link resolution: whether to resolve linked events
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Read last 10 events from a stream
    /// let events = try await client.readStream(.init(name: "orders")) { options in
    ///     options
    ///         .startFrom(revision: .end)
    ///         .backward()
    ///         .limit(10)
    /// }
    ///
    /// for try await response in events {
    ///     if case .event(let event) = response {
    ///         print("Event \(event.event.eventNumber): \(event.event.eventType)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to read from.
    ///   - configure: A closure to configure read options. Defaults to reading forward
    ///     from the beginning with no limit.
    ///
    /// - Returns: An async throwing stream of read responses containing events.
    ///
    /// - Throws: `KurrentError` with specific cases:
    ///   - `.streamNotFound`: The specified stream does not exist
    ///   - `.streamDeleted`: The stream has been deleted
    ///   - `.accessDenied`: Insufficient permissions to read the stream
    ///
    /// - SeeAlso: `Streams.Read.Options`, `ReadEvent`, `StreamRevision`
    public func readStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).read(options: options)
    }
}

// MARK: - Stream Subscription Operations

extension KurrentDBClient {
    /// Creates a real-time subscription to the `$all` stream.
    ///
    /// Subscriptions provide a persistent connection to the server that delivers events
    /// as they are committed. Unlike read operations that return a snapshot, subscriptions
    /// continue delivering events indefinitely until explicitly cancelled.
    ///
    /// ## Configuration Options
    ///
    /// Use the `configure` closure to set:
    /// - Start position: where to begin in the event stream
    /// - Event filters: by event type or stream name
    /// - Checkpoint interval: for tracking subscription progress
    ///
    /// ## Example
    ///
    /// ```swift
    /// let subscription = try await client.subscribeAllStreams { options in
    ///     options
    ///         .startFrom(position: .end)  // Only new events
    ///         .filterBy(eventTypes: ["OrderCreated"])
    /// }
    ///
    /// for try await event in subscription.events {
    ///     // Process event
    ///     print("New event: \(event.event.eventType)")
    /// }
    /// ```
    ///
    /// - Parameter configure: A closure to configure subscription options. Defaults to
    ///   subscribing from the end (live-only events).
    ///
    /// - Returns: A subscription object providing access to the event stream.
    ///
    /// - Throws: `KurrentError` if the subscription fails to start.
    ///
    /// - Important: Subscriptions maintain an active connection. Always call `cancel()`
    ///   on the subscription when done to release server resources.
    ///
    /// - SeeAlso: `Streams.SubscribeAll.Options`, `Streams.Subscription`
    public func subscribeAllStreams(configure: @Sendable (Streams<AllStreams>.SubscribeAll.Options) -> Streams<AllStreams>.SubscribeAll.Options = { $0 }) async throws -> Streams<AllStreams>.Subscription {
        let options = configure(.init())
        return try await streams(of: .all).subscribe(options: options)
    }

    /// Creates a real-time subscription to a specific stream.
    ///
    /// Establishes a persistent connection that delivers events from the specified stream
    /// as they are written. The subscription will receive both catch-up events (if starting
    /// before stream end) and live events as they occur.
    ///
    /// ## Catch-Up and Live Phases
    ///
    /// 1. **Catch-up**: Delivers historical events from start position to current stream end
    /// 2. **Live**: Delivers new events as they are written to the stream
    ///
    /// ## Example
    ///
    /// ```swift
    /// let subscription = try await client.subscribeStream(
    ///     .init(name: "orders")
    /// ) { options in
    ///     options.startFrom(revision: .start)  // Process all events
    /// }
    ///
    /// Task {
    ///     for try await event in subscription.events {
    ///         await processOrder(event)
    ///     }
    /// }
    ///
    /// // Later, cancel when done
    /// subscription.cancel()
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to subscribe to.
    ///   - configure: A closure to configure subscription options. Defaults to subscribing
    ///     from the end (live-only events).
    ///
    /// - Returns: A subscription object providing access to the event stream.
    ///
    /// - Throws: `KurrentError` with specific cases:
    ///   - `.streamNotFound`: The specified stream does not exist
    ///   - `.accessDenied`: Insufficient permissions to subscribe
    ///
    /// - Note: Subscriptions automatically recover from transient network failures.
    ///
    /// - SeeAlso: `Streams.Subscribe.Options`, `Streams.Subscription`
    public func subscribeStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).subscribe(options: options)
    }
}

// MARK: - Stream Deletion Operations

extension KurrentDBClient {
    /// Soft deletes a stream, marking it as deleted but preserving events.
    ///
    /// A soft delete makes the stream unavailable for normal operations but preserves
    /// the underlying event data. The stream can potentially be recovered, and events
    /// remain visible in the `$all` stream. This is the recommended deletion method
    /// for most scenarios.
    ///
    /// ## Soft Delete Behavior
    ///
    /// - Stream becomes inaccessible via normal read operations
    /// - Events remain in the database and `$all` stream
    /// - Stream metadata is preserved
    /// - Disk space is not immediately reclaimed
    /// - Stream can potentially be recovered by server administrators
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.deleteStream(.init(name: "temp-stream")) { options in
    ///     options.revision(expected: .streamExists)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to delete.
    ///   - configure: A closure to configure deletion options, including expected revision
    ///     for optimistic concurrency control. Defaults to no configuration (`.any` revision).
    ///
    /// - Returns: A delete response confirming the operation.
    ///
    /// - Throws: `KurrentError` with specific cases:
    ///   - `.wrongExpectedVersion`: Expected revision does not match
    ///   - `.streamDeleted`: Stream is already deleted
    ///   - `.accessDenied`: Insufficient permissions
    ///
    /// - SeeAlso: `tombstoneStream(_:configure:)`, `Streams.Delete.Options`
    @discardableResult
    public func deleteStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).delete(options: options)
    }

    /// Hard deletes (tombstones) a stream, permanently preventing future writes.
    ///
    /// A tombstone operation permanently marks the stream name as unusable. Unlike soft
    /// delete, tombstoning prevents the stream name from ever being reused. This is
    /// useful for ensuring business rule invariants where certain streams must never
    /// be recreated.
    ///
    /// ## Tombstone Behavior
    ///
    /// - Stream name becomes permanently reserved and unusable
    /// - No new events can ever be written to this stream name
    /// - Events remain in database and `$all` stream
    /// - Stream cannot be recovered or recreated
    /// - Attempting to write raises a stream-deleted error
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Permanently prevent writes to a sensitive stream
    /// try await client.tombstoneStream(.init(name: "audit-2023")) { options in
    ///     options.revision(expected: .streamExists)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to tombstone.
    ///   - configure: A closure to configure tombstone options, including expected revision.
    ///     Defaults to no configuration (`.any` revision).
    ///
    /// - Returns: A tombstone response confirming the operation.
    ///
    /// - Throws: `KurrentError` with specific cases:
    ///   - `.wrongExpectedVersion`: Expected revision does not match
    ///   - `.accessDenied`: Insufficient permissions
    ///
    /// - Warning: This operation is irreversible. The stream name can never be reused.
    ///
    /// - SeeAlso: `deleteStream(_:configure:)`, `Streams.Tombstone.Options`
    @discardableResult
    public func tombstoneStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).tombstone(options: options)
    }
}

// MARK: - Convenience Methods (String-based)

extension KurrentDBClient {
    /// Sets metadata for a stream identified by name.
    ///
    /// This is a convenience method equivalent to calling `setStreamMetadata(_:metadata:expectedRevision:)`
    /// with a `StreamIdentifier` created from the stream name. Refer to that method's documentation
    /// for detailed information about stream metadata.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to set metadata for.
    ///   - metadata: The metadata configuration to apply.
    ///   - expectedRevision: The expected revision for optimistic concurrency control. Defaults to `.any`.
    ///
    /// - Returns: The append response containing the new revision number.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - SeeAlso: `setStreamMetadata(_:metadata:expectedRevision:)`, `StreamMetadata`
    @discardableResult
    public func setStreamMetadata(_ streamName: String, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamName)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves metadata for a stream identified by name.
    ///
    /// This is a convenience method equivalent to calling `getStreamMetadata(_:)` with a
    /// `StreamIdentifier` created from the stream name. Returns `nil` if no custom metadata
    /// has been set for the stream.
    ///
    /// - Parameter streamName: The name of the stream to retrieve metadata for.
    ///
    /// - Returns: The stream's metadata configuration, or `nil` if no custom metadata exists.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - SeeAlso: `getStreamMetadata(_:)`, `StreamMetadata`
    public func getStreamMetadata(_ streamName: String) async throws -> StreamMetadata? {
        try await streams(of: .specified(streamName)).getMetadata()
    }

    /// Appends events to a stream identified by name.
    ///
    /// This is a convenience method that accepts a stream name string instead of a
    /// `StreamIdentifier`. It is functionally equivalent to the identifier-based version
    /// but provides a more concise syntax for common use cases.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let events = [
    ///     EventData(eventType: "ItemAdded", model: ["itemId": "456"])
    /// ]
    ///
    /// try await client.appendToStream("cart-123", events: events) {
    ///     $0.revision(expected: .streamExists)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - events: An array of events to append in order.
    ///   - configure: A closure to configure append options. Defaults to no configuration.
    ///
    /// - Returns: An append response containing the next expected revision.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - SeeAlso: `appendToStream(_:events:configure:)`, `EventData`
    @discardableResult
    public func appendToStream(_ streamName: String, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    /// Appends one or more events to a stream using variadic parameters.
    ///
    /// This overload accepts events as variadic parameters for ergonomic single or
    /// few-event appends without requiring explicit array construction.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.appendToStream(
    ///     "orders",
    ///     EventData(eventType: "OrderCreated", model: order),
    ///     EventData(eventType: "EmailSent", model: notification)
    /// ) {
    ///     $0.revision(expected: .noStream)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - events: One or more events to append.
    ///   - configure: A closure to configure append options. Defaults to no configuration.
    ///
    /// - Returns: An append response containing the next expected revision.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - SeeAlso: `appendToStream(_:events:configure:)`, `EventData`
    @discardableResult
    public func appendToStream(_ streamName: String, events: EventData..., configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    /// Reads events from a stream identified by name.
    ///
    /// This is a convenience method that accepts a stream name string instead of a
    /// `StreamIdentifier`. Refer to `readStream(_:configure:)` for detailed documentation.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to read from.
    ///   - configure: A closure to configure read options. Defaults to no configuration.
    ///
    /// - Returns: An async throwing stream of read responses containing events.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - SeeAlso: `readStream(_:configure:)`, `Streams.Read.Options`
    @available(*, deprecated, renamed: "readStream")
    public func readStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).read(options: options)
    }

    /// Creates a real-time subscription to a stream identified by name.
    ///
    /// This is a convenience method that accepts a stream name string instead of a
    /// `StreamIdentifier`. Refer to `subscribeStream(_:configure:)` for detailed documentation.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to subscribe to.
    ///   - configure: A closure to configure subscription options. Defaults to no configuration.
    ///
    /// - Returns: A subscription object providing access to the event stream.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - SeeAlso: `subscribeStream(_:configure:)`, `Streams.Subscribe.Options`
    public func subscribeStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).subscribe(options: options)
    }

    /// Soft deletes a stream identified by name.
    ///
    /// This is a convenience method that accepts a stream name string instead of a
    /// `StreamIdentifier`. Refer to `deleteStream(_:configure:)` for detailed documentation
    /// about soft deletion behavior.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to delete.
    ///   - configure: A closure to configure deletion options. Defaults to no configuration.
    ///
    /// - Returns: A delete response confirming the operation.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - SeeAlso: `deleteStream(_:configure:)`, `Streams.Delete.Options`
    @discardableResult
    public func deleteStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).delete(options: options)
    }

    /// Hard deletes (tombstones) a stream identified by name.
    ///
    /// This is a convenience method that accepts a stream name string instead of a
    /// `StreamIdentifier`. Refer to `tombstoneStream(_:configure:)` for detailed documentation
    /// about tombstoning behavior.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to tombstone.
    ///   - configure: A closure to configure tombstone options. Defaults to no configuration.
    ///
    /// - Returns: A tombstone response confirming the operation.
    ///
    /// - Throws: `KurrentError` if the operation fails.
    ///
    /// - Warning: This operation is irreversible. The stream name can never be reused.
    ///
    /// - SeeAlso: `tombstoneStream(_:configure:)`, `Streams.Tombstone.Options`
    @discardableResult
    public func tombstoneStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).tombstone(options: options)
    }
}
