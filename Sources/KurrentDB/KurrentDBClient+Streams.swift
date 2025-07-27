//
//  KurrentDBClient+Streams.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides convenience methods for stream operations.
extension KurrentDBClient {
    @discardableResult
    public func setStreamMetadata(_ streamIdentifier: StreamIdentifier, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamIdentifier)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    public func getStreamMetadata(_ streamIdentifier: StreamIdentifier) async throws -> StreamMetadata? {
        try await streams(of: .specified(streamIdentifier)).getMetadata()
    }

    @discardableResult
    public func appendStream(_ streamIdentifier: StreamIdentifier, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }

    public func readAllStreams(configure: @Sendable (Streams<AllStreams>.ReadAll.Options) -> Streams<AllStreams>.ReadAll.Options = { $0 }) async throws -> Streams<AllStreams>.ReadAll.Responses {
        let options = configure(.init())
        return try await streams(of: .all).read(options: options)
    }

    public func readStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).read(options: options)
    }

    public func subscribeAllStreams(configure: @Sendable (Streams<AllStreams>.SubscribeAll.Options) -> Streams<AllStreams>.SubscribeAll.Options = { $0 }) async throws -> Streams<AllStreams>.Subscription {
        let options = configure(.init())
        return try await streams(of: .all).subscribe(options: options)
    }

    public func subscribeStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).subscribe(options: options)
    }

    @discardableResult
    public func deleteStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).delete(options: options)
    }

    @discardableResult
    public func tombstoneStream(_ streamIdentifier: StreamIdentifier, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).tombstone(options: options)
    }

    public func copyStream(_ fromIdentifier: StreamIdentifier, toNewStream newIdentifier: StreamIdentifier) async throws {
        let readResponses = try await streams(of: .specified(fromIdentifier)).read(options: .init().resolveLinks())
        let events = try await readResponses.reduce(into: [EventData]()) { partialResult, response in
            let recordedEvent = try response.event.record
            let event = EventData(like: recordedEvent)
            partialResult.append(event)
        }
        try await streams(of: .specified(newIdentifier)).append(events: events, options: .init().revision(expected: .noStream))
    }

    @discardableResult
    public func setStreamMetadata(_ streamName: String, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamName)).setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    public func getStreamMetadata(_ streamName: String) async throws -> StreamMetadata? {
        try await streams(of: .specified(streamName)).getMetadata()
    }

    @discardableResult
    public func appendStream(_ streamName: String, events: [EventData], configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    @discardableResult
    public func appendStream(_ streamName: String, events: EventData..., configure: @Sendable (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).append(events: events, options: options)
    }

    public func readStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).read(options: options)
    }

    public func subscribeStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).subscribe(options: options)
    }

    @discardableResult
    public func deleteStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).delete(options: options)
    }

    @discardableResult
    public func tombstoneStream(_ streamName: String, configure: @Sendable (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamName)).tombstone(options: options)
    }
}
