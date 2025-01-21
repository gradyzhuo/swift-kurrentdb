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
import Streams
import Operations
import PersistentSubscriptions


/// `EventStoreDBClient`
/// A client to encapsulates GRPC Call in EventStoreDB.
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
    public func setMetadata(to identifier: KurrentCore.Stream.Identifier, metadata: KurrentCore.Stream.Metadata, configure: (_ options: Streams.Append.Options) -> Streams.Append.Options) async throws -> Streams.Append.Response.Success {
        try await appendStream(
            to: .init(name: "$$\(identifier.name)"),
            events: .init(
                eventType: "$metadata",
                payload: metadata
            ),
            configure: configure
        )
    }

    public func getStreamMetadata(to identifier: KurrentCore.Stream.Identifier, cursor: Cursor<Streams.ReadCursorPointer> = .end) async throws -> KurrentCore.Stream.Metadata? {
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
    public func appendStream(to identifier: KurrentCore.Stream.Identifier, events: [EventData], configure: (_ options: Streams.Append.Options) -> Streams.Append.Options) async throws -> Streams.Append.Response.Success {
        let options = configure(.init())
        let streams = Streams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.append(to: identifier, events: events, options: options)
    }
    
    public func appendStream(to identifier: KurrentCore.Stream.Identifier, events: EventData..., configure: (_ options: Streams.Append.Options) -> Streams.Append.Options = { $0 }) async throws -> Streams.Append.Response.Success {
        try await appendStream(to: identifier, events: events, configure: configure)
    }

    // MARK: Read by all streams methods -

    public func readAllStreams(cursor: Cursor<Streams.ReadAll.CursorPointer>, configure: (_ options: Streams.Read.Options) -> Streams.Read.Options = { $0 }) async throws -> Streams.Read.Responses {
        let options = configure(.init())
        let streams = Streams.Service(settings: settings, callOptions: defaultCallOptions)
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
    public func readStream(to streamIdentifier: KurrentCore.Stream.Identifier, cursor: Cursor<Streams.ReadCursorPointer>, configure: (_ options: Streams.Read.Options) -> Streams.Read.Options = { $0 }) async throws -> Streams.Read.Responses {
        let options = configure(.init())
        let streams = Streams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.read(streamIdentifier, cursor: cursor, options: options)
    }

    public func readStream(to streamIdentifier: KurrentCore.Stream.Identifier, at revision: UInt64, direction: KurrentCore.Stream.Direction = .forward, configure: (_ options: Streams.Read.Options) -> Streams.Read.Options = { $0 }) async throws -> Streams.Read.Responses {
        let cursor: Cursor<Streams.ReadCursorPointer> = .specified(.init(revision: revision, direction: direction))
        return try await readStream(to: streamIdentifier, cursor: cursor, configure: configure)
    }

    // MARK: Subscribe by all streams methods -

    public func subscribeToAll(from cursor: KurrentCore.Cursor<KurrentCore.Stream.Position>, configure: (_ options: Streams.SubscribeToAll.Options) -> Streams.SubscribeToAll.Options = { $0 }) async throws -> Streams.Subscription {
        let options = configure(.init())
        let streams = Streams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.subscribeToAll(cursor: cursor, options: options)
    }

    public func subscribeTo(stream: KurrentCore.Stream.Identifier, from cursor: KurrentCore.Cursor<KurrentCore.Stream.Revision>, configure: (_ options: Streams.Subscribe.Options) -> Streams.Subscribe.Options = { $0 }) async throws -> Streams.Subscription {
        let options = configure(.init())
        let streams = Streams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.subscribe(stream, cursor: cursor, options: options)
    }

    // MARK: (Soft) Delete a stream -

    @discardableResult
    public func deleteStream(to identifier: KurrentCore.Stream.Identifier, configure: (_ options: Streams.Delete.Options) -> Streams.Delete.Options) async throws -> Streams.Delete.Response {
        let options = configure(.init())
        let streams = Streams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.delete(identifier, options: options)
    }

    // MARK: (Hard) Delete a stream -

    @discardableResult
    public func tombstoneStream(to identifier: KurrentCore.Stream.Identifier, configure: (_ options: Streams.Tombstone.Options) -> Streams.Tombstone.Options) async throws -> Streams.Tombstone.Response {
        let options = configure(.init())
        let streams = Streams.Service(settings: settings, callOptions: defaultCallOptions)
        return try await streams.tombstone(identifier, options: options)
    }
}

// MARK: - Operations

extension EventStoreDBClient {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> Operations.ScavengeResponse {
        let operations = Operations.Service(settings: settings, callOptions: defaultCallOptions)
        return try await operations.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }
    
    public func stopScavenge(scavengeId: String) async throws -> Operations.ScavengeResponse {
        let operations = Operations.Service(settings: settings, callOptions: defaultCallOptions)
        return try await operations.stopScavenge(scavengeId: scavengeId)
    }
}

//MARK: - PersistentSubscriptions
extension EventStoreDBClient {
    public func createPersistentSubscription(to identifier: KurrentCore.Stream.Identifier, groupName: String, configure: (_ options: PersistentSubscriptions.CreateToStream.Options) -> PersistentSubscriptions.CreateToStream.Options = { $0 }) async throws {
        let options = configure(.init())
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.createToStream(streamIdentifier: identifier, groupName: groupName, options: options)
    }

    public func createPersistentSubscriptionToAll(groupName: String, configure: (_ options: PersistentSubscriptions.CreateToAll.Options) -> PersistentSubscriptions.CreateToAll.Options = { $0 }) async throws {
        
        let options = configure(.init())
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.createToAll(groupName: groupName, options: options)
    }
    
    // MARK: Delete PersistentSubscriptions
    public func deletePersistentSubscription(streamSelector: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String) async throws {
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.delete(stream: streamSelector, groupName: groupName)
    }
    
    // MARK: List PersistentSubscriptions
    public func listPersistentSubscription(streamSelector: KurrentCore.Selector<KurrentCore.Stream.Identifier>) async throws -> [PersistentSubscription.SubscriptionInfo]{
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.list(streamSelector: streamSelector)
    }

    // MARK: - Restart Subsystem Action

    public func restartPersistentSubscriptionSubsystem() async throws {
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        try await persistentSubscriptions.restartSubsystem()
    }

    // MARK: -

    public func subscribePersistentSubscription(to streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String, configure: (_ options: PersistentSubscriptions.Read.Options) -> PersistentSubscriptions.Read.Options = { $0 }) async throws -> PersistentSubscriptions.Subscription {
        let options = configure(.init())
        let persistentSubscriptions = PersistentSubscriptions.Service(settings: settings, callOptions: defaultCallOptions)
        return try await persistentSubscriptions.subscribe(streamSelection, groupName: groupName, options: options)
    }
}
