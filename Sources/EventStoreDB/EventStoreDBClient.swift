//
//  EventStoreDBClient.swift
//
//
//  Created by Grady Zhuo on 2024/3/18.
//

import Foundation
import GRPC
import GRPCEncapsulates
import NIOCore
import NIOPosix

/// `EventStoreDBClient`
/// A client to encapsulates GRPC Call in EventStoreDB.
public final class EventStoreDBClient: Sendable {
    public let defaultCallOptions: CallOptions
    public let settings: ClientSettings
    private let group: EventLoopGroup
    
    /// construct `EventStoreDBClient`  with `ClientSettings` and `numberOfThreads`.
    /// - Parameters:
    ///   - settings: encapsulates various configuration settings for a client.
    ///   - numberOfThreads: the number of threads of `EventLoopGroup` in `NIOChannel`.
    public init(settings: ClientSettings, numberOfThreads: Int = 1) {
        var defaultCallOptions = CallOptions()
        if let credentials = settings.defaultUserCredentials {
            do {
                try defaultCallOptions.customMetadata.replaceOrAdd(name: "Authorization", value: credentials.makeBasicAuthHeader())
            } catch {
                logger.error("Could not setting Authorization with credentials: \(credentials).\n Original error:\(error).")
            }
        }
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }
    
}

// MARK: - Streams Operations

extension EventStoreDBClient {
    @discardableResult
    public func setMetadata(to identifier: Stream.Identifier, metadata: Stream.Metadata, configure: (_ options: StreamClient.Append.Options) -> StreamClient.Append.Options) async throws -> StreamClient.Append.Response.Success {
        try await appendStream(
            to: .init(name: "$$\(identifier.name)"),
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
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = StreamClient(channel: channel, callOptions: defaultCallOptions)
        let options = configure(.init())
        return try await client.appendTo(stream: identifier, events: events, options: options)
    }
        

    public func appendStream(to identifier: Stream.Identifier, events: EventData..., configure: (_ options: StreamClient.Append.Options) -> StreamClient.Append.Options = { $0 }) async throws -> StreamClient.Append.Response.Success {
        try await appendStream(to: identifier, events: events, configure: configure)
    }

    // MARK: Read by all streams methods -

    public func readAllStreams(cursor: Cursor<StreamClient.ReadAll.CursorPointer>, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = StreamClient(channel: channel, callOptions: defaultCallOptions)

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
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = StreamClient(channel: channel, callOptions: defaultCallOptions)
        let options = configure(.init())
        
        return try client.read(stream: streamIdentifier, cursor: cursor, options: options)
    }

    public func readStream(to streamIdentifier: Stream.Identifier, at revision: UInt64, direction: Stream.Direction = .forward, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        let cursor: Cursor<StreamClient.Read.CursorPointer> = .specified(.init(revision: revision, direction: direction))
        return try readStream(to: streamIdentifier, cursor: cursor, configure: configure)
    }

    // MARK: Subscribe by all streams methods -

    public func subscribeToAll(from cursor: Cursor<Stream.Position>, configure: (_ options: StreamClient.SubscribeToAll.Options) -> StreamClient.SubscribeToAll.Options = { $0 }) async throws -> StreamClient.Subscription {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = StreamClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.subscribeToAll(from: cursor, options: options)
    }

    public func subscribeTo(stream: Stream.Identifier, from cursor: Cursor<Stream.Revision>, configure: (_ options: StreamClient.Subscribe.Options) -> StreamClient.Subscribe.Options = { $0 }) async throws -> StreamClient.Subscription {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = StreamClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.subscribe(stream: stream, from: cursor, options: options)
    }

    // MARK: (Soft) Delete a stream -

    @discardableResult
    public func deleteStream(to identifier: Stream.Identifier, configure: (_ options: StreamClient.Delete.Options) -> StreamClient.Delete.Options) async throws -> StreamClient.Delete.Response {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = StreamClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.delete(identifier: identifier, options: options, channel: channel, callOptions: defaultCallOptions)

    }

    // MARK: (Hard) Delete a stream -

    @discardableResult
    public func tombstoneStream(to identifier: Stream.Identifier, configure: (_ options: StreamClient.Tombstone.Options) -> StreamClient.Tombstone.Options) async throws -> StreamClient.Tombstone.Response {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = StreamClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.tombstone(identifier: identifier, options: options, channel: channel, callOptions: defaultCallOptions)
    }
}

// MARK: - Operations

extension EventStoreDBClient {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> OperationsClient.ScavengeResponse {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = OperationsClient(channel: channel, callOptions: defaultCallOptions)
        return try await client.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }
}

extension EventStoreDBClient {
    public func createPersistentSubscription(to identifier: Stream.Identifier, groupName: String, configure: (_ options: PersistentSubscriptionsClient.Create.ToStream.Options) -> PersistentSubscriptionsClient.Create.ToStream.Options = { $0 }) async throws {
        
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        
        let options = configure(.init())
        try await client.createToStream(streamIdentifier: identifier, groupName: groupName, options: options)
        
    }

    public func createPersistentSubscriptionToAll(groupName: String, configure: (_ options: PersistentSubscriptionsClient.Create.ToAll.Options) -> PersistentSubscriptionsClient.Create.ToAll.Options = { $0 }) async throws {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        
        let options = configure(.init())
        try await client.createToAll(groupName: groupName, options: options)
    }
    
    // MARK: Delete PersistentSubscriptions
    public func deletePersistentSubscription(streamSelector: Selector<Stream.Identifier>, groupName: String) async throws {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        try await client.deleteOn(stream: streamSelector, groupName: groupName)
    }
    
    // MARK: List PersistentSubscriptions
    public func listPersistentSubscription(streamSelector: Selector<Stream.Identifier>) async throws -> [PersistentSubscriptionsClient.GetInfo.SubscriptionInfo]{
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        return try await client.list(streamSelector: streamSelector)
    }

    // MARK: - Restart Subsystem Action

    public func restartPersistentSubscriptionSubsystem() async throws {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        return try await client.restartSubsystem()
    }

    // MARK: -

    public func subscribePersistentSubscription(to streamSelection: Selector<Stream.Identifier>, groupName: String, configure: (_ options: PersistentSubscriptionsClient.Read.Options) -> PersistentSubscriptionsClient.Read.Options = { $0 }) async throws -> PersistentSubscriptionsClient.Subscription {
        let channel = try GRPCChannelPool.with(settings: settings, group: group)
        let client = PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)

        let options = configure(.init())
        return try await client.subscribeTo(streamSelection, groupName: groupName, options: options)
    }
}
