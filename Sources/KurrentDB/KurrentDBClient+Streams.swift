//
//  KurrentDBClient+Streams.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides convenience methods for stream operations.
extension KurrentDBClient {
    /// Sets metadata for a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - metadata: The metadata to associate with the stream.
    ///   - expectedRevision: The expected revision of the stream for concurrency control, defaulting to `.any`.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the metadata cannot be set.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func setStreamMetadata(_ streamIdentifier: StreamIdentifier, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamIdentifier)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves metadata for a specific stream.
    ///
    /// - Parameter streamIdentifier: The identifier of the target stream.
    /// - Returns: The `StreamMetadata` if available, otherwise `nil`.
    /// - Throws: An error if the metadata cannot be retrieved.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func getStreamMetadata(_ streamIdentifier: StreamIdentifier) async throws -> StreamMetadata? {
        return try await streams(of: .specified(streamIdentifier)).getMetadata()
    }
    
    /// Appends events to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - events: An array of events to append.
    ///   - configure: A closure to customize the append options, defaulting to no modifications.
    /// - Returns: An `Append.Response` indicating the result.
    /// - Throws: An error if the append operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func appendStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }
    
    /// Reads events from all streams.
    ///
    /// - Parameters:
    ///   - cursor: The starting position for reading, defaulting to `.start`.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    /// - Throws: An error if the read operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func readAllStreams(since cursor: PositionCursor = .start, configure: @Sendable (Streams<AllStreams>.ReadAll.Options) -> Streams<AllStreams>.ReadAll.Options = { $0 }) async throws -> Streams<AllStreams>.ReadAll.Responses {
        let options = configure(.init())
        return try await streams(of: .all).read(startFrom: cursor, options: options)
    }
    
    /// Reads events from a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - cursor: The starting revision for reading, defaulting to `.start`.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    /// - Throws: An error if the read operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func readStream(_ streamIdentifier: StreamIdentifier, since cursor: RevisionCursor = .start, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).read(startFrom: cursor, options: options)
    }
    
    /// Subscribes to all streams.
    ///
    /// - Parameters:
    ///   - cursor: The starting position for the subscription, defaulting to `.start`.
    ///   - configure: A closure to customize the subscription options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func subscribeAllStreams(since cursor: PositionCursor = .start, configure: @Sendable (Streams<AllStreams>.SubscribeAll.Options) -> Streams<AllStreams>.SubscribeAll.Options = { $0 }) async throws -> Streams<AllStreams>.Subscription {
        let options = configure(.init())
        return try await streams(of: .all).subscribe(startFrom: cursor, options: options)
    }
    
    /// Subscribes to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - configure: A closure to customize the subscription options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func subscribeStream(_ streamIdentifier: StreamIdentifier, since cursor: RevisionCursor = .end, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).subscribe(startFrom: cursor, options: options)
    }
    
    /// Deletes a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - configure: A closure to customize the delete options, defaulting to no modifications.
    /// - Returns: A `Delete.Response` indicating the result.
    /// - Throws: An error if the delete operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func deleteStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).delete(options: options)
    }
    
    /// Tombstones a specific stream, marking it as permanently deleted.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - configure: A closure to customize the tombstone options, defaulting to no modifications.
    /// - Returns: A `Tombstone.Response` indicating the result.
    /// - Throws: An error if the tombstone operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func tombstoneStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).tombstone(options: options)
    }
    
    /// Copies events from one stream to a new stream.
    ///
    /// - Parameters:
    ///   - fromIdentifier: The identifier of the source stream.
    ///   - toNewStream: The identifier of the destination stream.
    /// - Throws: An error if the copy operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func copyStream(_ fromIdentifier: StreamIdentifier, toNewStream newIdentifier: StreamIdentifier) async throws {
        let readResponses = try await streams(of: .specified(fromIdentifier)).read(options: .init().resolveLinks())
        let events = try await readResponses.reduce(into: [EventData]()) { partialResult, response in
            let recordedEvent = try response.event.record
            let event = EventData(like: recordedEvent)
            partialResult.append(event)
        }
        try await streams(of: .specified(newIdentifier)).append(events: events, options: .init().revision(expected: .noStream))
    }
    
    /// Sets metadata for a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - metadata: The metadata to associate with the stream.
    ///   - expectedRevision: The expected revision of the stream for concurrency control, defaulting to `.any`.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the metadata cannot be set.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func setStreamMetadata(_ streamName: String, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamName)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves metadata for a specific stream using its name.
    ///
    /// - Parameter streamName: The name of the target stream.
    /// - Returns: The `StreamMetadata` if available, otherwise `nil`.
    /// - Throws: An error if the metadata cannot be retrieved.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func getStreamMetadata(_ streamName: String) async throws -> StreamMetadata? {
        return try await streams(of: .specified(streamName)).getMetadata()
    }
    
    /// Appends events to a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - events: An array of events to append.
    ///   - configure: A closure to customize the append options, defaulting to no modifications.
    /// - Returns: An `Append.Response` indicating the result.
    /// - Throws: An error if the append operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func appendStream(_ streamName: String, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }
    
    /// Appends variadic events to a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - events: A variadic list of events to append.
    ///   - configure: A closure to customize the append options, defaulting to no modifications.
    /// - Returns: An `Append.Response` indicating the result.
    /// - Throws: An error if the append operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func appendStream(_ streamName: String, events: EventData..., configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    /// Reads events from a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - cursor: The starting revision for reading, defaulting to `.start`.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    /// - Throws: An error if the read operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func readStream(_ streamName: String, since cursor: RevisionCursor = .start, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).read(startFrom: cursor, options: options)
    }
    
    /// Subscribes to a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - configure: A closure to customize the subscription options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func subscribeStream(_ streamName: String, since cursor: RevisionCursor = .end, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).subscribe(startFrom: cursor, options: options)
    }
    
    /// Deletes a specific stream using its name.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - configure: A closure to customize the delete options, defaulting to no modifications.
    /// - Returns: A `Delete.Response` indicating the result.
    /// - Throws: An error if the delete operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func deleteStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).delete(options: options)
    }
    
    /// Tombstones a specific stream using its name, marking it as permanently deleted.
    ///
    /// - Parameters:
    ///   - streamName: The name of the target stream.
    ///   - configure: A closure to customize the tombstone options, defaulting to no modifications.
    /// - Returns: A `Tombstone.Response` indicating the result.
    /// - Throws: An error if the tombstone operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    @discardableResult
    public func tombstoneStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).tombstone(options: options)
    }
}
