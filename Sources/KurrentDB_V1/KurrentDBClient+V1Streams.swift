//
//  KurrentDBClient+V1Streams.swift
//  swift-kurrentdb
//
//  Compatibility layer — convenience methods for stream operations.
//  Prefer the target-based API: client.streams(of:), client.streams(specified:),
//  client.allStreams, client.multiStreams
//

import KurrentDB

@available(*, deprecated, message: "Use the target-based API instead: client.streams(of:), client.streams(specified:), client.allStreams, client.multiStreams")
extension KurrentDBClient {

    // MARK: - Stream Metadata Operations

    /// Sets metadata for a stream identified by its StreamIdentifier.
    @discardableResult
    public func setStreamMetadata(_ streamIdentifier: StreamIdentifier, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamIdentifier)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves metadata for a stream identified by its StreamIdentifier.
    public func getStreamMetadata(_ streamIdentifier: StreamIdentifier) async throws(KurrentError) -> StreamMetadata? {
        try await streams(of: .specified(streamIdentifier)).getMetadata()
    }

    /// Sets metadata for a stream identified by name.
    @discardableResult
    public func setStreamMetadata(_ streamName: String, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamName)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves metadata for a stream identified by name.
    public func getStreamMetadata(_ streamName: String) async throws(KurrentError) -> StreamMetadata? {
        try await streams(of: .specified(streamName)).getMetadata()
    }

    // MARK: - Stream Append Operations

    /// Appends events to a stream identified by its StreamIdentifier.
    @discardableResult
    public func appendToStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }

    /// Appends events to multiple streams in a single batch operation.
    @discardableResult
    public func appendToStreams(events: [StreamEvent]) async throws(KurrentError) -> Streams<MultiStreams>.AppendSession.Response {
        try await streams(of: .multiple).append(events: events)
    }

    /// Appends events to a stream identified by name.
    @discardableResult
    public func appendToStream(_ streamName: String, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    /// Appends one or more events to a stream using variadic parameters.
    @discardableResult
    public func appendToStream(_ streamName: String, events: EventData..., configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    // MARK: - Stream Read Operations

    /// Reads events from the `$all` stream (global event log).
    public func readAllStreams(configure: @Sendable (Streams<AllStreams>.ReadAll.Options) -> Streams<AllStreams>.ReadAll.Options = { $0 }) async throws(KurrentError) -> Streams<AllStreams>.ReadAll.Responses {
        let options = configure(.init())
        return try await streams(of: .all).read(options: options)
    }

    /// Reads events from a specific stream identified by its StreamIdentifier.
    public func readStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).read(options: options)
    }

    /// Reads events from a stream identified by name.
    @available(*, deprecated, renamed: "readStream")
    public func readStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).read(options: options)
    }

    // MARK: - Stream Subscription Operations

    /// Creates a real-time subscription to the `$all` stream.
    public func subscribeAllStreams(configure: @Sendable (Streams<AllStreams>.SubscribeAll.Options) -> Streams<AllStreams>.SubscribeAll.Options = { $0 }) async throws(KurrentError) -> Streams<AllStreams>.Subscription {
        let options = configure(.init())
        return try await streams(of: .all).subscribe(options: options)
    }

    /// Creates a real-time subscription to a specific stream identified by its StreamIdentifier.
    public func subscribeStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).subscribe(options: options)
    }

    /// Creates a real-time subscription to a stream identified by name.
    public func subscribeStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).subscribe(options: options)
    }

    // MARK: - Stream Deletion Operations

    /// Soft deletes a stream identified by its StreamIdentifier.
    @discardableResult
    public func deleteStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).delete(options: options)
    }

    /// Hard deletes (tombstones) a stream identified by its StreamIdentifier.
    @discardableResult
    public func tombstoneStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).tombstone(options: options)
    }

    /// Soft deletes a stream identified by name.
    @discardableResult
    public func deleteStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).delete(options: options)
    }

    /// Hard deletes (tombstones) a stream identified by name.
    @discardableResult
    public func tombstoneStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).tombstone(options: options)
    }

    // MARK: - Deprecated (from KurrentDBClient+Deprecated.swift)

    /// Appends a batch of events to a specified stream (deprecated).
    @available(*, deprecated, renamed: "appendToStream")
    @discardableResult
    public func appendStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }

    /// Appends a batch of events to a stream identified by name (deprecated).
    @available(*, deprecated, renamed: "appendToStream")
    @discardableResult
    public func appendStream(_ streamName: String, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    /// Appends one or more events to a stream identified by name using variadic parameters (deprecated).
    @available(*, deprecated, renamed: "appendToStream")
    @discardableResult
    public func appendStream(_ streamName: String, events: EventData..., configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws(KurrentError) -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }
}
