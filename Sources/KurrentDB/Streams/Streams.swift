//
//  Streams.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

/// A generic gRPC service for handling event streams.
///
/// `Streams` enables interaction with event streams through operations such as appending, reading,
/// subscribing, deleting, and managing metadata. It is a concrete implementation of `GRPCConcreteService`.
///
/// The type parameter `Target` determines the scope of the stream, allowing either a specific stream
/// (`SpecifiedStream`), a projection stream (`ProjectionStream`), or all streams (`AllStreams`).
///
/// ## Usage
///
/// Creating a client for a specified stream and appending events:
/// ```swift
/// let specifiedStream = Streams(target: StreamTarget.specified("log.txt"), settings: clientSettings)
/// try await specifiedStream.append(events: [event])
/// ```
///
/// Reading from all streams:
/// ```swift
/// let allStreams = Streams(target: StreamTarget.all, settings: clientSettings)
/// let responses = try await allStreams.read(cursor: .start)
/// for try await response in responses {
///     print(response)
/// }
/// ```
///
/// - Note: This service relies on **gRPC** and requires a valid `ClientSettings` configuration.
///
/// ### Topics
/// #### Specific Stream Operations
/// - ``setMetadata(metadata:)``
/// - ``getMetadata(cursor:)``
/// - ``append(events:options:)``
/// - ``read(cursor:options:)``
/// - ``subscribe(from:options:)``
/// - ``delete(options:)``
/// - ``tombstone(options:)``
///
/// #### Projection Stream Operations
/// - ``subscribe(from:options:)-swift.struct-8y6e8``
///
/// #### All Streams Operations
/// - ``read(cursor:options:)-6h8h2``
/// - ``subscribe(from:options:)-9gq2e``
public struct Streams<Target: StreamTarget>: GRPCConcreteService {
    
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Streams_Streams.Client<HTTP2ClientTransport.Posix>

    /// The client settings required for establishing a gRPC connection.
    public let settings: ClientSettings
    
    /// The gRPC call options.
    public let callOptions: CallOptions
    
    /// The event loop group handling asynchronous tasks.
    public let eventLoopGroup: EventLoopGroup
    
    /// The target stream, defining the scope of operations (e.g., specific stream or all streams).
    public let target: Target

    /// Initializes a `Streams` instance with a target and settings.
    ///
    /// - Parameters:
    ///   - target: The stream target (e.g., `SpecifiedStream`, `ProjectionStream`, or `AllStreams`).
    ///   - settings: The client settings for gRPC communication.
    ///   - callOptions: The gRPC call options, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group, defaulting to a shared multi-threaded group.
    internal init(target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - Specified Stream Operations
/// Provides operations for specific streams conforming to `SpecifiedStreamTarget`.
extension Streams where Target: SpecifiedStreamTarget {
    
    /// The identifier of the specific stream.
    public var identifier: StreamIdentifier {
        get {
            target.identifier
        }
    }

    /// Sets metadata for the specified stream.
    ///
    /// - Parameter metadata: The metadata to associate with the stream.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func setMetadata(metadata: StreamMetadata) async throws -> Append.Response {
        let usecase = Append(to: .init(name: "$$\(identifier.name)"), events: [
            .init(
                eventType: "$metadata",
                payload: metadata
            )
        ], options: .init())
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Retrieves the metadata associated with the specified stream.
    ///
    /// - Parameter cursor: The position in the stream from which to retrieve metadata, defaulting to `.end`.
    /// - Returns: The `StreamMetadata` if available, otherwise `nil`.
    /// - Throws: An error if the metadata cannot be retrieved or parsed.
    @discardableResult
    public func getMetadata(cursor: Cursor<CursorPointer> = .end) async throws -> StreamMetadata? {
        let options: Streams.Read.Options = .init()
                                            .cursor(.start)
                                            .forward()
        let usecase = Read(from: .init(name: "$$\(identifier.name)"), options: options)
        let responses = try await usecase.perform(settings: settings, callOptions: callOptions)

        return try await responses.first {
            if case .event = $0 { return true }
            return false
        }.flatMap {
            switch $0 {
            case let .event(event):
                switch event.record.contentType {
                case .json:
                    try JSONDecoder().decode(StreamMetadata.self, from: event.record.data)
                default:
                    throw ClientError.eventDataError(message: "The event data could not be parsed. Stream metadata must be encoded in JSON format.")
                }
            default:
                throw ClientError.readResponseError(message: "The metadata event does not exist.")
            }
        }
    }

    /// Appends a list of events to the specified stream.
    ///
    /// - Parameters:
    ///   - events: An array of events to append.
    ///   - options: The options for appending events. Defaults to an empty configuration.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the append operation fails.
    @discardableResult
    public func append(events: [EventData], options: Append.Options = .init()) async throws -> Append.Response {
        let usecase = Append(to: identifier, events: events, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Appends a variadic list of events to the specified stream.
    ///
    /// - Parameters:
    ///   - events: A variadic list of events to append.
    ///   - options: The options for appending events. Defaults to an empty configuration.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the append operation fails.
    @discardableResult
    public func append(events: EventData..., options: Append.Options = .init()) async throws -> Append.Response {
        return try await append(events: events, options: options)
    }

    /// Reads events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to read.
    ///   - options: The options for reading events. Defaults to an empty configuration.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    /// - Throws: An error if the read operation fails.
    public func read(from cursor: Read.Cursor = .start, options: Read.Options = .init()) async throws -> AsyncThrowingStream<Read.Response, Error> {
        let usecase = Read(from: identifier, options: options.cursor(cursor))
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to start subscribing.
    ///   - options: The options for subscribing. Defaults to an empty configuration.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribe(from cursor: Read.Cursor = .end, options: Subscribe.Options = .init()) async throws -> Subscription {
        let usecase = Subscribe(from: identifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Subscribes to events from the specified stream starting at a given revision.
    ///
    /// - Parameters:
    ///   - revision: The revision of the stream to start subscribing from.
    ///   - options: The options for subscribing. Defaults to an empty configuration.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribe(fromRevision revision: UInt64, options: Subscribe.Options = .init()) async throws -> Subscription {
        return try await subscribe(from: .revision(revision), options: options)
    }

    /// Deletes the specified stream.
    ///
    /// - Parameter options: The options for deleting the stream. Defaults to an empty configuration.
    /// - Returns: A `Delete.Response` indicating the result of the operation.
    /// - Throws: An error if the delete operation fails.
    @discardableResult
    public func delete(options: Delete.Options = .init()) async throws -> Delete.Response {
        let usecase = Delete(to: identifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Marks the specified stream as permanently deleted (tombstoned).
    ///
    /// - Parameter options: The options for tombstoning the stream. Defaults to an empty configuration.
    /// - Returns: A `Tombstone.Response` indicating the result of the operation.
    /// - Throws: An error if the tombstone operation fails.
    @discardableResult
    public func tombstone(options: Tombstone.Options = .init()) async throws -> Tombstone.Response {
        let usecase = Tombstone(to: identifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

/// Provides operations for projection streams.
extension Streams where Target == ProjectionStream {
    
    /// The identifier of the projection stream.
    public var identifier: StreamIdentifier {
        get {
            target.identifier
        }
    }

    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to start subscribing.
    ///   - options: The options for subscribing. Defaults to an empty configuration.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribe(from cursor: Read.Cursor, options: Subscribe.Options = .init()) async throws -> Subscription {
        let usecase = Subscribe(from: identifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

}

// MARK: - All Streams Operations
/// Provides operations for all streams.
extension Streams where Target == AllStreams {

    /// Reads events from all available streams.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to start reading.
    ///   - options: The options for reading events. Defaults to an empty configuration.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    /// - Throws: An error if the read operation fails.
    public func read(from cursor: ReadAll.Cursor,options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        let usecase = ReadAll(options: options.curosr(cursor))
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Subscribes to all streams from a specified position.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to start subscribing.
    ///   - options: The options for subscribing. Defaults to an empty configuration.
    /// - Returns: A `Streams.Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribe(from cursor: Cursor<StreamPosition>, options: SubscribeAll.Options = .init()) async throws -> Streams.Subscription {
        let usecase = SubscribeAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
}
