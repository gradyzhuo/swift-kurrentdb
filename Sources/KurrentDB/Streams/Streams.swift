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
/// let specifiedStream = Streams(target: StreamsTarget.specified("log.txt"), settings: clientSettings)
/// try await specifiedStream.append(events: [event])
/// ```
///
/// Reading from all streams:
/// ```swift
/// let allStreams = Streams(target: StreamsTarget.all, settings: clientSettings)
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
public actor Streams<Target: StreamsTarget>: GRPCConcreteService {
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Streams_Streams.Client<HTTP2ClientTransport.Posix>

    /// The client settings required for establishing a gRPC connection.
    public private(set) var selector: NodeSelector

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
    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - Specified Stream Operations

/// Provides operations for specific streams conforming to `SpecifiedStreamTarget`.
extension Streams where Target: SpecifiedStreamTarget {
    /// The identifier of the specific stream.
    public var identifier: StreamIdentifier {
        target.identifier
    }

    /// Sets metadata for the specified stream.
    ///
    /// - Parameter metadata: The metadata to associate with the stream.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the operation fails.
    @discardableResult
    public func setMetadata(metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws(KurrentError) -> Append.Response {
        let usecase = Append(to: .init(name: "$$\(identifier.name)"), events: [
            .init(
                eventType: "$metadata",
                model: metadata
            ),
        ], options: .init().revision(expected: expectedRevision))
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Retrieves the metadata associated with the specified stream.
    ///
    /// - Parameter cursor: The position in the stream from which to retrieve metadata, defaulting to `.end`.
    /// - Returns: The `StreamMetadata` if available, otherwise `nil`.
    /// Retrieves the latest metadata for the stream, if available.
    ///
    /// Reads the most recent metadata event from the stream's metadata stream (`$$<streamName>`), decodes it as JSON, and returns it as a `StreamMetadata` object. Returns `nil` if no metadata event exists.
    ///
    /// - Throws: `KurrentError` if the metadata event is missing, not in JSON format, or if a parsing or client error occurs.
    ///
    /// Retrieves the latest metadata for the stream, decoding it as `StreamMetadata`.
    ///
    /// Reads the most recent metadata event from the stream's associated metadata stream. Returns the decoded metadata if present, or `nil` if no metadata event exists. Throws an error if the event data is not valid JSON or if a client or parsing error occurs.
    ///
    /// - Returns: The latest `StreamMetadata` if available, or `nil` if no metadata event exists.
    @discardableResult
    public func getMetadata() async throws(KurrentError) -> StreamMetadata? {
        let options: Streams.Read.Options = .init().startFrom(revision: .end).backward().limit(1)
        let usecase = Read(from: .init(name: "$$\(identifier.name)"), options: options)
        let responses = try await usecase.perform(selector: selector, callOptions: callOptions)

        do {
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
                        throw KurrentError.internalParsingError(reason: "The event data could not be parsed. Stream metadata must be encoded in JSON format.")
                    }
                default:
                    throw KurrentError.initializationError(reason: "The metadata event does not exist.")
                }
            }
        } catch {
            throw .internalClientError(reason: "\(#function) failed, cause: \(error)")
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
    public func append(events: [EventData], options: Append.Options = .init()) async throws(KurrentError) -> Append.Response {
        let usecase = Append(to: identifier, events: events, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Appends a variadic list of events to the specified stream.
    ///
    /// - Parameters:
    ///   - events: A variadic list of events to append.
    ///   - options: The options for appending events. Defaults to an empty configuration.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the append operation fails.
    @discardableResult
    public func append(events: EventData..., options: Append.Options = .init()) async throws(KurrentError) -> Append.Response {
        try await append(events: events, options: options)
    }
    
    /// Reads events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to read.
    ///   - options: The options for reading events. Defaults to an empty configuration.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    /// Reads events from the specified stream as an asynchronous throwing stream.
    ///
    /// - Parameter options: Options to configure the read operation, such as revision range or filters.
    /// - Returns: An asynchronous throwing stream of read responses containing events from the stream.
    /// - Throws: `KurrentError` if the read operation fails.
    public func read(options: Read.Options = .init()) async throws(KurrentError) -> AsyncThrowingStream<Read.Response, Error> {
        let usecase = Read(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to start subscribing.
    ///   - options: The options for subscribing. Defaults to an empty configuration.
    /// - Returns: A `Subscription` instance for receiving events.
    /// Subscribes to events from the specified stream.
    ///
    /// - Parameter options: Subscription options, such as filters or starting revision.
    /// - Returns: A subscription to the stream's events.
    /// - Throws: `KurrentError` if the subscription fails.
    public func subscribe(options: Subscribe.Options = .init()) async throws(KurrentError) -> Subscription {
        let usecase = Subscribe(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Deletes the specified stream.
    ///
    /// - Parameter options: The options for deleting the stream. Defaults to an empty configuration.
    /// - Returns: A `Delete.Response` indicating the result of the operation.
    /// - Throws: An error if the delete operation fails.
    @discardableResult
    public func delete(options: Delete.Options = .init()) async throws(KurrentError) -> Delete.Response {
        let usecase = Delete(to: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Marks the specified stream as permanently deleted (tombstoned).
    ///
    /// - Parameter options: The options for tombstoning the stream. Defaults to an empty configuration.
    /// - Returns: A `Tombstone.Response` indicating the result of the operation.
    /// - Throws: An error if the tombstone operation fails.
    @discardableResult
    public func tombstone(options: Tombstone.Options = .init()) async throws(KurrentError) -> Tombstone.Response {
        let usecase = Tombstone(to: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

/// Provides operations for projection streams.
extension Streams where Target == ProjectionStream {
    /// The identifier of the projection stream.
    public var identifier: StreamIdentifier {
        target.identifier
    }

    /// Subscribes to events from the specified stream.
    ///
    /// - Parameters:
    ///   - cursor: The position in the stream from which to start subscribing.
    ///   - options: The options for subscribing. Defaults to an empty configuration.
    /// - Returns: A `Subscription` instance for receiving events.
    /// Subscribes to events from the specified stream.
    ///
    /// - Parameter options: Subscription options, such as filters or starting revision.
    /// - Returns: A subscription that receives events from the stream.
    /// - Throws: `KurrentError` if the subscription cannot be established.
    public func subscribe(options: Subscribe.Options = .init()) async throws(KurrentError) -> Subscription {
        let usecase = Subscribe(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - Multiple Streams Operations

extension Streams where Target == MultiStreams{
    
    /// Appends a batch of pre-constructed stream events using an append session. (KurrentDB > 25.1)
    ///
    /// Use this when you already have fully-formed `StreamEvent` values (including
    /// their event IDs, types, content type, and data) and want to persist them in
    /// a single session. This is useful for advanced scenarios like idempotent
    /// writes, preserving event IDs across retries, or when events are built
    /// incrementally by upstream systems.
    ///
    /// - Parameter events: The collection of `StreamEvent` values to append in order.
    /// - Returns: An `AppendSession.Response` describing the outcome of the session,
    ///   including the next expected revision and any server-assigned positions.
    /// - Throws: `KurrentError` if the session could not be established or the write
    ///   fails, for example due to version conflicts, access issues, or transport errors.
    @discardableResult
    public func append(events: [StreamEvent]) async throws(KurrentError) -> AppendSession.Response {
        let usecase = AppendSession(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Appends a variadic list of pre-constructed stream events in a single append session.  (KurrentDB > 25.1)
    ///
    /// Use this when you already have fully formed `StreamEvent` values (including IDs,
    /// types, content type, and payload) and want to persist them together while preserving
    /// ordering and event IDs. This is useful for idempotent writes, retries, or when events
    /// are assembled upstream.
    ///
    /// - Parameter events: One or more `StreamEvent` values to append in order.
    /// - Returns: An `AppendSession.Response` describing the outcome, including the next
    ///   expected revision and any server-assigned positions.
    /// - Throws: `KurrentError` if the session cannot be established or the write fails
    ///   (e.g., due to version conflicts, access issues, or transport errors).
    /// - Note: Events are appended in the order provided and are not transformed; ensure
    ///   each `StreamEvent` carries the desired identifiers and content metadata.
    @discardableResult
    public func append(events: StreamEvent...) async throws(KurrentError) -> AppendSession.Response {
        let usecase = AppendSession(streamEvents: events)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - All Streams Operations

/// Provides operations for all streams.
extension Streams where Target == AllStreams {
    /// Reads events from all available streams.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to start reading. default is `.start`.
    ///   - options: The options for reading events. Defaults to an empty configuration.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    /// Reads events from all streams as an asynchronous throwing stream.
    ///
    /// - Parameter options: Options to configure the read operation, such as filters or limits.
    /// - Returns: An asynchronous throwing stream of read responses containing events from all streams.
    /// - Throws: `KurrentError` if the read operation fails.
    public func read(options: ReadAll.Options = .init()) async throws(KurrentError) -> AsyncThrowingStream<ReadAll.Response, Error> {
        let usecase = ReadAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Subscribes to all streams from a specified position.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to start subscribing. default is `.end`
    ///   - options: The options for subscribing. Defaults to an empty configuration.
    /// - Returns: A `Streams.Subscription` instance for receiving events.
    /// Subscribes to all event streams, delivering events as they occur.
    ///
    /// - Parameter options: Subscription options, including filters and starting position.
    /// - Returns: A subscription that receives events from all streams.
    /// - Throws: `KurrentError` if the subscription fails.
    public func subscribe(options: SubscribeAll.Options = .init()) async throws(KurrentError) -> Streams.Subscription {
        let usecase = SubscribeAll(options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
