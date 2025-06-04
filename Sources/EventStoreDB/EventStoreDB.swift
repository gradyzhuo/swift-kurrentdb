//
//  EventStoreDB.swift
//  EventStoreDB
//
//  Created by Grady Zhuo on 2024/3/18.
//

@_exported import KurrentDB
import GRPCCore
import NIO
import Foundation

/// `EventStoreDBClient`
/// A client to encapsulates GRPC usecases to EventStoreDB.
@available(*, deprecated, message: "Using the new api spec of KurrentDBClient instead.")
public struct EventStoreDBClient: Sendable {
    public private(set) var underlyingClient: KurrentDBClient
    
    public var defaultCallOptions: CallOptions{
        get async {
            await underlyingClient.defaultCallOptions
        }
    }
    
    public var settings: ClientSettings{
        get async {
            await underlyingClient.settings
        }
    }

    /// construct `KurrentDBClient`  with `ClientSettings` and `numberOfThreads`.
    /// - Parameters:
    ///   - settings: encapsulates various configuration settings for a client.
    ///   - numberOfThreads: the number of threads of `EventLoopGroup` in `NIOChannel`.
    ///   - defaultCallOptions: the default call options for all grpc calls in KurrentDBClient.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.underlyingClient = .init(settings: settings, numberOfThreads: numberOfThreads, defaultCallOptions: defaultCallOptions)
    }
}


// MARK: - Streams Operations
extension EventStoreDBClient {
    @available(*, deprecated, message: "Please use the new API KurrentDBClient(settings:numberOfThreads:).streams(identifier:).setMetadata(to:metadata) instead.")
    @discardableResult
    public func setMetadata(to identifier: StreamIdentifier, metadata: StreamMetadata, configure: @Sendable (_ options: Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await appendStream(
            to: .init(name: "$$\(identifier.name)"),
            events: .init(
                eventType: "$metadata",
                payload: metadata
            ),
            configure: configure
        )
    }

    @available(*, deprecated, message: "Please use the new API .streams(identifier:).getStreamMetadata(cursor:) instead.")
    public func getStreamMetadata(to identifier: StreamIdentifier, cursor: Cursor<CursorPointer> = .end) async throws -> StreamMetadata? {
        let responses = try await readStream(to:
            .init(name: "$$\(identifier.name)"),
            cursor: cursor)
        return try await responses.first {
            switch $0 {
            case .event:
                true
            default:
                false
            }
        }.flatMap {
            switch $0 {
            case let .event(readEvent):
                switch readEvent.recordedEvent.contentType {
                case .json:
                    try JSONDecoder().decode(StreamMetadata.self, from: readEvent.recordedEvent.data)
                default:
                    throw ClientError.eventDataError(message: "The data of event could not be parsed. ContentType of Stream Metadata should be encoded in .json format.")
                }
            default:
                throw ClientError.readResponseError(message: "The metadata event is not exist.")
            }
        }
    }

    // MARK: Append methods -
    @available(*, deprecated, message: "Please use the new API .streams(of:.specified()).append(events:options:) instead.")
    public func appendStream(to identifier: StreamIdentifier, events: [EventData], configure: @Sendable (_ options: Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options) async throws -> Streams<SpecifiedStream>.Append.Response {
        return try await underlyingClient.appendStream(identifier, events: events){ _ in
            configure(.init())
        }
    }
    
    @available(*, deprecated, message: "Please use the new API .streams(of:).append(events:options:) instead.")
    public func appendStream(to identifier: StreamIdentifier, events: EventData..., configure: @Sendable (_ options: Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await appendStream(to: identifier, events: events, configure: configure)
    }

    /// Reads events from all streams starting from the specified cursor position.
    ///
    /// The direction of reading (forward or backward) is determined by the cursor value or its associated direction. Returns a sequence of events from all streams, starting at the given position.
    ///
    /// - Parameters:
    ///   - cursor: The position in the event log from which to start reading (start, end, or a specified position).
    ///   - configure: An optional closure to further configure read options.
    ///
    /// - Returns: A sequence of responses containing events from all streams.
    ///
    /// - Throws: An error if the read operation fails.
    @available(*, deprecated, message: "Please use the new API .streams(of:.all).append(events:options:) instead.")
    public func readAllStreams(cursor _cursor: Cursor<Streams<AllStreams>.ReadAll.CursorPointer>, configure: @Sendable (_ options: Streams<AllStreams>.ReadAll.Options) -> Streams<AllStreams>.ReadAll.Options = { $0 }) async throws -> Streams<AllStreams>.ReadAll.Responses {
        var options = configure(.init())
        let cursor: PositionCursor
        switch _cursor {
        case .start:
            options = options.forward()
            cursor = .start
        case .end:
            options = options.backward()
            cursor = .end
        case .specified(let pointer):
            cursor = .specified(commit: pointer.position.commit, prepare: pointer.position.prepare)
            switch pointer.direction {
            case .backward:
                options = options.backward()
            case .forward:
                options = options.forward()
            }
        }
        
        let finalOptions = options
        
        return try await underlyingClient.readAllStreams{ _ in
            finalOptions.position(from: cursor)
        }
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
    /// Reads events from a specified stream starting from a given cursor position.
    ///
    /// The cursor determines the starting revision and read direction. This method is deprecated; use the corresponding method on `KurrentDBClient` instead.
    ///
    /// - Parameters:
    ///   - identifier: The stream to read from.
    ///   - cursor: The starting position and direction for reading events.
    ///   - configure: Optional closure to further configure read options.
    ///
    /// - Returns: The responses containing events read from the stream.
    @available(*, deprecated)
    public func readStream(to identifier: StreamIdentifier, cursor _cursor: Cursor<CursorPointer>, configure: @Sendable (_ options: Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        var options = configure(.init())
        let cursor: RevisionCursor
        switch _cursor {
        case .start:
            cursor = .start
            options = options.forward()
        case .end:
            cursor = .end
            options = options.backward()
        case .specified(let pointer):
            cursor = .specified(pointer.revision)
            switch pointer.direction {
            case .backward:
                options = options.backward()
            case .forward:
                options = options.forward()
            }
        }
        let finalOptions = options
        return try await underlyingClient.readStream(identifier){ _ in
            finalOptions.revision(from: cursor)
        }
    }

    @available(*, deprecated)
    public func readStream(to streamIdentifier: StreamIdentifier, at revision: UInt64, direction: Direction = .forward, configure: @Sendable (_ options: Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        try await readStream(
            to: streamIdentifier,
            cursor: .specified(.init(revision: revision, direction: direction)),
            configure: configure
        )
    }

    /// Subscribes to all streams from a specified position cursor.
    ///
    /// - Parameters:
    ///   - _cursor: The starting position for the subscription (start, end, or a specific position).
    ///   - configure: Optional closure to further configure subscription options.
    ///
    /// - Returns: A subscription to all streams, starting from the specified position.
    ///
    /// - Note: This method is deprecated. Use the corresponding method on `KurrentDBClient` instead.
    @available(*, deprecated)
    public func subscribeToAll(from _cursor: Cursor<StreamPosition>, configure: @Sendable (_ options: Streams<AllStreams>.SubscribeAll.Options) -> Streams<AllStreams>.SubscribeAll.Options = { $0 }) async throws -> Streams<AllStreams>.Subscription {
        let options = configure(.init())
        let cursor: PositionCursor = switch _cursor {
        case .start:
            .start
        case .end:
            .end
        case .specified(let position):
            .specified(commit: position.commit, prepare: position.prepare)
        }
        return try await underlyingClient.subscribeAllStreams{ _ in
            options.position(from: cursor)
        }
    }

    /// Subscribes to a specified stream from a given revision cursor.
    ///
    /// - Parameters:
    ///   - identifier: The stream to subscribe to.
    ///   - _cursor: The starting revision cursor for the subscription.
    ///   - configure: Optional closure to further configure subscription options.
    ///
    /// - Returns: A subscription to the specified stream starting from the given revision cursor.
    ///
    /// - Note: This method is deprecated. Use the corresponding method on `KurrentDBClient` instead.
    @available(*, deprecated)
    public func subscribeTo(stream identifier: StreamIdentifier, from _cursor: Cursor<StreamRevision>, configure: @Sendable (_ options: Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        let cursor: RevisionCursor
        switch _cursor {
        case .start:
            cursor = .start
        case .end:
            cursor = .end
        case .specified(let pointer):
            cursor = .specified(pointer.value)
        }
        return try await underlyingClient.subscribeStream(identifier){ _ in
            options.revision(from: cursor)
        }
    }

    // MARK: (Soft) Delete a stream -

    @available(*, deprecated)
    @discardableResult
    public func deleteStream(to identifier: StreamIdentifier, configure: @Sendable (_ options: Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options) async throws -> Streams<SpecifiedStream>.Delete.Response {
        return try await underlyingClient.deleteStream(identifier){ _ in
            configure(.init())
        }
    }

    // MARK: (Hard) Delete a stream -
    @available(*, deprecated)
    @discardableResult
    public func tombstoneStream(to identifier: StreamIdentifier, configure: @Sendable (_ options: Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        return try await underlyingClient.tombstoneStream(identifier){ _ in
            configure(.init())
        }
    }
}

// MARK: - Operations

extension EventStoreDBClient {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> Operations.ScavengeResponse {
        let node = try await underlyingClient.selector.select()
        return try await underlyingClient.operations.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }

    public func stopScavenge(scavengeId: String) async throws -> Operations.ScavengeResponse {
        let node = try await underlyingClient.selector.select()
        return try await underlyingClient.operations.stopScavenge(scavengeId: scavengeId)
    }
}

// MARK: - PersistentSubscriptions

extension EventStoreDBClient {
    @available(*, deprecated)
    public func createPersistentSubscription(to identifier: StreamIdentifier, groupName: String, startFrom cursor: RevisionCursor = .end, configure: @Sendable (_ options: PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options = { $0 }) async throws {
        try await underlyingClient.createPersistentSubscription(stream: identifier, groupName: groupName){ _ in
            configure(.init())
        }
    }

    @available(*, deprecated)
    public func createPersistentSubscriptionToAll(groupName: String, startFrom cursor: PositionCursor, configure: @Sendable (_ options: PersistentSubscriptions<PersistentSubscription.AllStream>.Create.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.Create.Options = { $0 }) async throws {
        return try await underlyingClient.createPersistentSubscriptionToAllStream(groupName: groupName){ _ in
            configure(.init())
        }
    }

    // MARK: Delete PersistentSubscriptions
    @available(*, deprecated)
    public func deletePersistentSubscription(streamSelector: StreamSelector<StreamIdentifier>, groupName: String) async throws {
        
        switch streamSelector {
        case .all:
            try await underlyingClient.deletePersistentSubscriptionToAllStream(groupName: groupName)
        case let .specified(streamIdentifier):
            try await underlyingClient.deletePersistentSubscription(stream: streamIdentifier, groupName: groupName)
        }
    }

    // MARK: List PersistentSubscriptions
    @available(*, deprecated)
    public func listPersistentSubscription(streamSelector: StreamSelector<StreamIdentifier>) async throws -> [PersistentSubscription.SubscriptionInfo] {
        switch streamSelector {
        case .all:
            return try await underlyingClient.listPersistentSubscriptionsToAllStream()
        case let .specified(streamIdentifier):
            return try await underlyingClient.listPersistentSubscriptions(stream: streamIdentifier)
        }
    }

    // MARK: - Restart Subsystem Action
    @available(*, deprecated)
    public func restartPersistentSubscriptionSubsystem() async throws {
        try await underlyingClient.restartPersistentSubscriptionSubsystem()
    }

    // MARK: -
    @available(*, deprecated)
    public func subscribePersistentSubscription(to streamSelector: StreamSelector<StreamIdentifier>, groupName: String, configure: @Sendable (_ options: PersistentSubscriptions<PersistentSubscription.AnyTarget>.ReadOptions) -> PersistentSubscriptions<PersistentSubscription.AnyTarget>.ReadOptions = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.AnyTarget>.Subscription {
        let node = try await underlyingClient.selector.select()
        let options = configure(.init())
        let usecase = PersistentSubscriptions<PersistentSubscription.AnyTarget>.ReadAnyTarget(streamSelector: streamSelector, group: groupName, options: options)
        return try await usecase.perform(node: node, callOptions: underlyingClient.defaultCallOptions)
    }
    
}


