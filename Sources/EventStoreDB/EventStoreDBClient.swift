//
//  EventStoreDBClient.swift
//
//
//  Created by Grady Zhuo on 2024/3/18.
//

import Foundation
import KurrentCore
import NIOCore
import NIOPosix
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCEncapsulates
import KurrentStreams
import KurrentOperations
import KurrentPersistentSubscriptions


/// `EventStoreDBClient`
/// A client to encapsulates GRPC Call in EventStoreDB.

@available(*, deprecated, message: "Use Several Service instead. e.g. Streams.Service")
public final class EventStoreDBClient {
    public let defaultCallOptions: CallOptions
    public let settings: ClientSettings
    private let group: EventLoopGroup
    
    /// construct `EventStoreDBClient`  with `ClientSettings` and `numberOfThreads`.
    /// - Parameters:
    ///   - settings: encapsulates various configuration settings for a client.
    ///   - numberOfThreads: the number of threads of `EventLoopGroup` in `NIOChannel`.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }
    
}
//
// MARK: - Streams Operations
extension EventStoreDBClient {
    @discardableResult
    public func setMetadata(to identifier: KurrentCore.Stream.Identifier, metadata: KurrentCore.Stream.Metadata, configure: (_ options: KurrentStreams.Append.Options) -> KurrentStreams.Append.Options) async throws -> KurrentStreams.Append.Response.Success {
        try await appendStream(
            to: .init(name: "$$\(identifier.name)"),
            events: .init(
                eventType: "$metadata",
                payload: metadata
            ),
            configure: configure
        )
    }

    public func getStreamMetadata(to identifier: KurrentCore.Stream.Identifier, cursor: Cursor<KurrentStreams.ReadCursorPointer> = .end) async throws -> KurrentCore.Stream.Metadata? {
        let responses = try await readStream(to:
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
    public func appendStream(to identifier: KurrentCore.Stream.Identifier, events: [EventData], configure: (_ options: KurrentStreams.Append.Options) -> KurrentStreams.Append.Options) async throws -> KurrentStreams.Append.Response.Success {
        let options = configure(.init())
        let streams = KurrentStreams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.append(to: identifier, events: events, options: options)
    }
    
    public func appendStream(to identifier: KurrentCore.Stream.Identifier, events: EventData..., configure: (_ options: KurrentStreams.Append.Options) -> KurrentStreams.Append.Options = { $0 }) async throws -> KurrentStreams.Append.Response.Success {
        try await appendStream(to: identifier, events: events, configure: configure)
    }

    // MARK: Read by all streams methods -

    public func readAllStreams(cursor: Cursor<KurrentStreams.ReadAll.CursorPointer>, configure: (_ options: KurrentStreams.Read.Options) -> KurrentStreams.Read.Options = { $0 }) async throws -> KurrentStreams.Read.Responses {
        let options = configure(.init())
        let streams = KurrentStreams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.readAll(cursor: cursor, options: options)
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
    public func readStream(to streamIdentifier: KurrentCore.Stream.Identifier, cursor: Cursor<KurrentStreams.ReadCursorPointer>, configure: (_ options: KurrentStreams.Read.Options) -> KurrentStreams.Read.Options = { $0 }) async throws -> KurrentStreams.Read.Responses {
        let options = configure(.init())
        let streams = KurrentStreams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.read(streamIdentifier, cursor: cursor, options: options)
    }

    public func readStream(to streamIdentifier: KurrentCore.Stream.Identifier, at revision: UInt64, direction: KurrentCore.Stream.Direction = .forward, configure: (_ options: KurrentStreams.Read.Options) -> KurrentStreams.Read.Options = { $0 }) async throws -> KurrentStreams.Read.Responses {
        return try await readStream(
            to: streamIdentifier,
            cursor: .specified(.init(revision: revision, direction: direction)),
            configure: configure)
    }

    // MARK: Subscribe by all streams methods -

    public func subscribeToAll(from cursor: KurrentCore.Cursor<KurrentCore.Stream.Position>, configure: (_ options: KurrentStreams.SubscribeToAll.Options) -> KurrentStreams.SubscribeToAll.Options = { $0 }) async throws -> KurrentStreams.Subscription {
        let options = configure(.init())
        let streams = KurrentStreams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.subscribeToAll(cursor: cursor, options: options)
    }

    public func subscribeTo(stream: KurrentCore.Stream.Identifier, from cursor: KurrentCore.Cursor<KurrentCore.Stream.Revision>, configure: (_ options: KurrentStreams.Subscribe.Options) -> KurrentStreams.Subscribe.Options = { $0 }) async throws -> KurrentStreams.Subscription {
        let options = configure(.init())
        let streams = KurrentStreams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.subscribe(stream, cursor: cursor, options: options)
    }

    // MARK: (Soft) Delete a stream -

    @discardableResult
    public func deleteStream(to identifier: KurrentCore.Stream.Identifier, configure: (_ options: KurrentStreams.Delete.Options) -> KurrentStreams.Delete.Options) async throws -> KurrentStreams.Delete.Response {
        let options = configure(.init())
        let streams = KurrentStreams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.delete(identifier, options: options)
    }

    // MARK: (Hard) Delete a stream -

    @discardableResult
    public func tombstoneStream(to identifier: KurrentCore.Stream.Identifier, configure: (_ options: KurrentStreams.Tombstone.Options) -> KurrentStreams.Tombstone.Options) async throws -> KurrentStreams.Tombstone.Response {
        let options = configure(.init())
        let streams = KurrentStreams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.tombstone(identifier, options: options)
    }
}

// MARK: - Operations

extension EventStoreDBClient {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> KurrentOperations.ScavengeResponse {
        let operations = KurrentOperations.Service(settings: settings, callOptions: defaultCallOptions)
        return try await operations.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }
    
    public func stopScavenge(scavengeId: String) async throws -> KurrentOperations.ScavengeResponse {
        let operations = KurrentOperations.Service(settings: settings, callOptions: defaultCallOptions)
        return try await operations.stopScavenge(scavengeId: scavengeId)
    }
}

//MARK: - PersistentSubscriptions
extension EventStoreDBClient {
    public func createPersistentSubscription(to identifier: KurrentCore.Stream.Identifier, groupName: String, configure: (_ options: KurrentPersistentSubscriptions.CreateToStream.Options) -> KurrentPersistentSubscriptions.CreateToStream.Options = { $0 }) async throws {
        let options = configure(.init())
        let persistentSubscriptions = KurrentPersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.createToStream(streamIdentifier: identifier, groupName: groupName, options: options)
    }

    public func createPersistentSubscriptionToAll(groupName: String, configure: (_ options: KurrentPersistentSubscriptions.CreateToAll.Options) -> KurrentPersistentSubscriptions.CreateToAll.Options = { $0 }) async throws {
        
        let options = configure(.init())
        let persistentSubscriptions = KurrentPersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.createToAll(groupName: groupName, options: options)
    }
    
    // MARK: Delete PersistentSubscriptions
    public func deletePersistentSubscription(streamSelector: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String) async throws {
        let persistentSubscriptions = KurrentPersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.delete(stream: streamSelector, groupName: groupName)
    }
    
    // MARK: List PersistentSubscriptions
    public func listPersistentSubscription(streamSelector: KurrentCore.Selector<KurrentCore.Stream.Identifier>) async throws -> [PersistentSubscription.SubscriptionInfo]{
        let persistentSubscriptions = KurrentPersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.list(streamSelector: streamSelector)
    }

    // MARK: - Restart Subsystem Action

    public func restartPersistentSubscriptionSubsystem() async throws {
        let persistentSubscriptions = KurrentPersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        try await persistentSubscriptions.restartSubsystem()
    }

    // MARK: -

    public func subscribePersistentSubscription(to streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String, configure: (_ options: KurrentPersistentSubscriptions.Read.Options) -> KurrentPersistentSubscriptions.Read.Options = { $0 }) async throws -> KurrentPersistentSubscriptions.Subscription {
        let options = configure(.init())
        let persistentSubscriptions = KurrentPersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.subscribe(streamSelection, groupName: groupName, options: options)
    }
}
