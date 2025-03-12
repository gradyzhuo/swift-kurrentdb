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
/// `Streams` is a concrete gRPC service that allows interaction with event streams
/// through operations such as appending, reading, subscribing, deleting, and managing metadata.
///
/// The type parameter `Target` determines the scope of the stream,
/// allowing either a specific stream (`SpecifiedStream`) or all streams (`AllStreams`).
///
/// ## Usage
///
/// Creating a client for a specified stream:
/// ```swift
/// let specifiedStream = Streams(stream: StreamTarget.specified("log.txt"), settings: clientSettings)
/// try await specifiedStream.append(events: [event])
/// ```
///
/// Creating a client for all streams:
/// ```swift
/// let allStreams = Streams(stream: StreamTarget.all, settings: clientSettings)
/// try await allStreams.read(cursor: .start)
/// ```
///
/// - Note: This service is built on top of **gRPC** and requires a valid `ClientSettings` configuration.
public struct Streams<Target: StreamTarget>: GRPCConcreteService {
    
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Streams_Streams.Client<HTTP2ClientTransport.Posix>

    /// The client settings required for establishing a gRPC connection.
    public let settings: ClientSettings
    
    /// The gRPC call options.
    public let callOptions: CallOptions
    
    /// The event loop group handling asynchronous tasks.
    public let eventLoopGroup: EventLoopGroup
    
    /// The target stream, which can be either a specific stream or all streams.
    public let target: Target

    /// Initializes a `Streams` instance with the given target and settings.
    ///
    /// - Parameters:
    ///   - target: The stream target, either `SpecifiedStream` or `AllStreams`.
    ///   - settings: The client settings for gRPC communication.
    ///   - callOptions: The gRPC call options, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group, defaulting to a shared multi-threaded group.
    public init(target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - Specified Stream Operations
extension Streams where Target: SpecifiedStreamTarget {
    
    /// The identifier of the specific stream.
    public var identifier: StreamIdentifier {
        get {
            target.identifier
        }
    }

    /// Sets metadata for the specified stream.
    ///
    /// - Parameter metadata: The metadata to be associated with the stream.
    /// - Returns: An `Append.Response` indicating the result of the operation.
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
    @discardableResult
    public func getMetadata(cursor: Cursor<CursorPointer> = .end) async throws -> StreamMetadata? {
        let usecase = Read(from: .init(name: "$$\(identifier.name)"), cursor: cursor, options: .init())
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
    ///   - events: The list of events to append.
    ///   - options: Options for appending events.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    public func append(events: [EventData], options: Append.Options = .init()) async throws -> Append.Response {
        let usecase = Append(to: identifier, events: events, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Appends a list of events to the specified stream.
    ///
    /// - Parameters:
    ///   - events:  The list of events to append by variadic parameters form.
    ///   - options: Options for appending events.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    public func append(events: EventData..., options: Append.Options = .init()) async throws -> Append.Response {
        return try await append(events: events, options: options)
    }

    /// Reads events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to read.
    ///   - options: Read options.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    public func read(cursor: Cursor<CursorPointer>, options: Read.Options = .init()) async throws -> AsyncThrowingStream<Read.Response, Error> {
        let usecase = Read(from: identifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Reads events from the specified stream.
    /// - Parameters:
    ///   - revision: The revision of the stream that will be read from it.
    ///   - direction: The direction to read.
    ///   - options: Read options.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    public func read(from revision: UInt64, directTo direction: Direction, options: Read.Options = .init()) async throws -> AsyncThrowingStream<Read.Response, Error> {
        return try await read(cursor: .specified(.init(revision: revision, direction: direction)), options: options)
    }
    
    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to subscribe.
    ///   - options: Subscription options.
    /// - Returns: A `Subscription` instance.
    public func subscribe(from cursor: Cursor<StreamRevision>, options: Subscribe.Options = .init()) async throws -> Subscription {
        let usecase = Subscribe(from: identifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - revision: The revision of the stream that will be read from it.
    ///   - direction: The direction to read.
    ///   - options: Subscription options.
    /// - Returns: A `Subscription` instance.
    public func subscribe(from revision: UInt64, options: Subscribe.Options = .init()) async throws -> Subscription {
        return try await subscribe(from: .specified(.init(value: revision)), options: options)
    }

    /// Deletes the specified stream.
    ///
    /// - Parameter options: Delete options.
    /// - Returns: A `Delete.Response` indicating the result of the operation.
    @discardableResult
    public func delete(options: Delete.Options = .init()) async throws -> Delete.Response {
        let usecase = Delete(to: identifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Marks the specified stream as permanently deleted (tombstoned).
    ///
    /// - Parameter options: Tombstone options.
    /// - Returns: A `Tombstone.Response` indicating the result of the operation.
    @discardableResult
    public func tombstone(options: Tombstone.Options = .init()) async throws -> Tombstone.Response {
        let usecase = Tombstone(to: identifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Streams where Target == ProjectionStream {
    
    /// The identifier of the specific stream.
    public var identifier: StreamIdentifier {
        get {
            target.identifier
        }
    }

    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to subscribe.
    ///   - options: Subscription options.
    /// - Returns: A `Subscription` instance.
    public func subscribe(from cursor: Cursor<StreamRevision>, options: Subscribe.Options = .init()) async throws -> Subscription {
        let usecase = Subscribe(from: identifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - revision: The revision of the stream that will be read from it.
    ///   - direction: The direction to read.
    ///   - options: Subscription options.
    /// - Returns: A `Subscription` instance.
    public func subscribe(from revision: UInt64, options: Subscribe.Options = .init()) async throws -> Subscription {
        return try await subscribe(from: .specified(.init(value: revision)), options: options)
    }
}

// MARK: - All Streams Operations
extension Streams where Target == AllStreams {

    /// Reads events from all available streams.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to read.
    ///   - options: Read options.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    public func read(cursor: Cursor<ReadAll.CursorPointer>, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        let usecase = ReadAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Reads events from a specified position and direction in all streams.
    ///
    /// - Parameters:
    ///   - position: The starting position in the stream.
    ///   - direction: The reading direction.
    ///   - options: Read options.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    public func read(from position: StreamPosition, directTo direction: Direction, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        try await read(cursor: .specified(.init(position: position, direction: direction)), options: options)
    }

    /// Subscribes to all streams from a specified position.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to subscribe.
    ///   - options: Subscription options.
    /// - Returns: A `Streams.Subscription` instance.
    public func subscribe(from cursor: Cursor<StreamPosition>, options: SubscribeAll.Options = .init()) async throws -> Streams.Subscription {
        let usecase = SubscribeAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
