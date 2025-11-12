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

    /// Appends events to the specified stream using the stream identifier.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the stream to append events to.
    ///   - events: The events to append to the stream.
    ///   - configure: A closure to configure the append options. Defaults to no configuration.
    /// - Returns: The response from appending the events to the stream.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func appendStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }

    /// Reads all events from the "all-stream" starting from the specified position.
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

    /// Subscribes to events from the "all-stream" starting from the specified position.
    ///
    /// - Parameter configure: A closure to configure the subscription options. Defaults to no configuration.
    /// - Returns: The subscription to the "all-stream".
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

    /// Copies all events from one stream to another new stream.
    ///
    /// - Parameters:
    ///   - fromIdentifier: The identifier of the source stream to copy events from.
    ///   - toNewStream: The identifier of the new stream to copy events to.
    /// - Throws: An error if the operation fails.
    public func copyStream(_ fromIdentifier: StreamIdentifier, toNewStream newIdentifier: StreamIdentifier) async throws {
        let readResponses = try await streams(of: .specified(fromIdentifier)).read(options: .init().resolveLinks())
        let events = try await readResponses.reduce(into: [EventData]()) { partialResult, response in
            let recordedEvent = try response.event.record
            let event = EventData(like: recordedEvent)
            partialResult.append(event)
        }
        try await streams(of: .specified(newIdentifier)).append(events: events, options: .init().revision(expected: .noStream))
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
