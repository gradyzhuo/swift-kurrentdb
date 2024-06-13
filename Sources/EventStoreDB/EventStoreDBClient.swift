//
//  EventStoreDBClient.swift
//
//
//  Created by Grady Zhuo on 2024/3/18.
//

import Foundation
import GRPC
import GRPCEncapsulates

public struct EventStoreDBClient {
    var channel: GRPCChannel {
        get throws {
            try GRPCChannelPool.with(settings: settings)
        }
    }

    public var defaultCallOptions: CallOptions
    public var settings: ClientSettings

    public init(settings: ClientSettings) {
        var defaultCallOptions = CallOptions()
        if let credentials = settings.defaultUserCredentials {
            do{
                try defaultCallOptions.customMetadata.replaceOrAdd(name: "Authorization", value: credentials.makeBasicAuthHeader())
            }catch{
                logger.error("Could not setting Authorization with credentials: \(credentials).\n Original error:\(error).")
            }
        }
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
    }
}

// MARK: - Streams Operations

extension EventStoreDBClient {
    public func setMetadata(streamName: String, metadata: Stream.Metadata, configure: (_ options: StreamClient.Append.Options) -> StreamClient.Append.Options) async throws -> StreamClient.Append.Response.Success {
        try await appendStream(
            to: .init(name: "$$\(streamName)"),
            events: .init(
                eventType: "$metadata",
                payload: metadata
            ),
            configure: configure
        )
    }

    public func getStreamMetadata(to identifier: Stream.Identifier, cursor: Cursor<StreamClient.Read.CursorPointer> = .end) async throws -> Stream.Metadata? {
        let responses = try readStream(to:
            .init(name: "$$\(identifier.name)"),
            cursor: cursor)
        return try await responses.first {
            switch $0.content {
            case .event:
                true
            default:
                false
            }
        }.flatMap {
            switch $0.content {
            case let .event(readEvent):
                switch readEvent.recordedEvent.contentType {
                case .json:
                    try JSONDecoder().decode(Stream.Metadata.self, from: readEvent.recordedEvent.data)
                default:
                    throw ClientError.eventDataError(message: "The data of event could not be parsed. ContentType of Stream Metadata should be encoded in .json format.")
                }
            default:
                throw ClientError.readResponseError(message: "The metadata event is not exist.")
            }
        }
    }

    // MARK: Append methods -

    public func appendStream(to identifier: Stream.Identifier, events: [EventData], configure: (_ options: StreamClient.Append.Options) -> StreamClient.Append.Options) async throws -> StreamClient.Append.Response.Success {
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)
        let options = configure(.init())

        return try await client.appendTo(stream: identifier, events: events, options: options)
    }

    public func appendStream(to identifier: Stream.Identifier, events: EventData ..., configure: (_ options: StreamClient.Append.Options) -> StreamClient.Append.Options = { $0 }) async throws -> StreamClient.Append.Response.Success {
        try await appendStream(to: identifier, events: events, configure: configure)
    }

    // MARK: Read by all streams methods -

    public func readAllStreams(cursor: Cursor<StreamClient.ReadAll.CursorPointer>, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try client.readAll(cursor: cursor, options: options, channel: channel, callOptions: defaultCallOptions)
    }

    // MARK: Read by a stream methos -

    /// Read all events from a stream.
    /// - Parameters:
    ///   - to: the identifier of stream.
    ///   - cursor: the revision of stream that we want to read from.
    ///        - start: Read the stream from start revision and forward to the end.
    ///        - end:  Read the stream from end revision and backward to the start.  (It is a reverse operation to `start`.)
    ///        - specified:
    ///            - forwardOn(revision): Read the stream from the assigned revision and forward to the end.
    ///            - backwardFrom(revision):  Read the stream from the assigned revision and backward to the start.
    ///   - configure: A closure of building read options.
    /// - Returns: AsyncStream to Read.Response
    public func readStream(to streamIdentifier: Stream.Identifier, cursor: Cursor<StreamClient.Read.CursorPointer>, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)
        let options = configure(.init())

        return try client.read(stream: streamIdentifier, cursor: cursor, options: options)
    }

    public func readStream(to streamIdentifier: Stream.Identifier, at revision: UInt64, direction: StreamClient.Read.Direction = .forward, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        let cursor: Cursor<StreamClient.Read.CursorPointer> = .specified(.init(revision: revision, direction: direction))
        return try readStream(to: streamIdentifier, cursor: cursor, configure: configure)
    }

    // MARK: (Soft) Delete a stream -

    @discardableResult
    public func deleteStream(to identifier: Stream.Identifier, configure: (_ options: StreamClient.Delete.Options) -> StreamClient.Delete.Options) async throws -> StreamClient.Delete.Response {
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.delete(identifier: identifier, options: options, channel: channel, callOptions: defaultCallOptions)
    }

    // MARK: (Hard) Delete a stream -

    @discardableResult
    public func tombstoneStream(to identifier: Stream.Identifier, configure: (_ options: StreamClient.Tombstone.Options) -> StreamClient.Tombstone.Options) async throws -> StreamClient.Tombstone.Response {
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.tombstone(identifier: identifier, options: options, channel: channel, callOptions: defaultCallOptions)
    }
}

// MARK: - Operations

extension EventStoreDBClient {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> OperationsClient.ScavengeResponse {
        let client = try OperationsClient(channel: channel, callOptions: defaultCallOptions)
        return try await client.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }
}

extension EventStoreDBClient {
    public func createPersistentSubscription(to identifier: Stream.Identifier, groupName: String, options: PersistentSubscriptionsClient.Create.ToStream.Options = .init()) async throws {
        let underlyingClient = try PersistentSubscriptionsClient.UnderlyingClient(channel: channel, defaultCallOptions: defaultCallOptions)
        let handler: PersistentSubscriptionsClient.Create.ToStream = .init(streamIdentifier: identifier, groupName: groupName, options: options)

        let request = try handler.build()

        try await handler.handle(response: underlyingClient.create(request))
    }

    public func createPersistentSubscriptionToAll(groupName: String, options: PersistentSubscriptionsClient.Create.ToAll.Options = .init()) async throws {
        let underlyingClient = try PersistentSubscriptionsClient.UnderlyingClient(channel: channel, defaultCallOptions: defaultCallOptions)
        let handler: PersistentSubscriptionsClient.Create.ToAll = .init(groupName: groupName, options: options)

        let request = try handler.build()
        try await handler.handle(response: underlyingClient.create(request))
    }

    // MARK: - Restart Subsystem Action

    public func restartPersistentSubscriptionSubsystem() async throws {
        let client = try PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        return try await client.restartSubsystem()
    }

    // MARK: -

    public func subscribePersistentSubscription(to streamSelection: Selector<Stream.Identifier>, groupName: String, configure: (_ options: PersistentSubscriptionsClient.Read.Options) -> PersistentSubscriptionsClient.Read.Options = { $0 }) async throws -> PersistentSubscriptionsClient.Subscription {
        let client = try PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.subscribeTo(streamSelection, groupName: groupName, options: options)
    }
}
