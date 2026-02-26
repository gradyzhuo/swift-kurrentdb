//
//  Streams+SpecifiedStreamTarget.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//

import Foundation

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
        var options = Append.Options()
        options.expectedRevision = expectedRevision
        let usecase = Append(to: .init(name: "$$\(identifier.name)"), events: [
            .init(
                eventType: "$metadata",
                model: metadata
            ),
        ], options: options)
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
        var options = Streams.Read.Options()
        options.revision = .end
        options.direction = .backward
        options.limit = 1
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
    ///   - configure: A closure to configure append options. Defaults to no-op.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the append operation fails.
    @discardableResult
    public func append(events: [EventData], configure: @Sendable (inout Append.Options) -> Void = { _ in }) async throws(KurrentError) -> Append.Response {
        var options = Append.Options()
        configure(&options)
        let usecase = Append(to: identifier, events: events, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Appends a variadic list of events to the specified stream.
    ///
    /// - Parameters:
    ///   - events: A variadic list of events to append.
    ///   - configure: A closure to configure append options. Defaults to no-op.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the append operation fails.
    @discardableResult
    public func append(events: EventData..., configure: @Sendable (inout Append.Options) -> Void = { _ in }) async throws(KurrentError) -> Append.Response {
        try await append(events: events, configure: configure)
    }

    /// Reads events from the specified stream.
    ///
    /// - Parameter configure: A closure to configure read options, such as revision range or direction. Defaults to no-op.
    /// - Returns: An asynchronous throwing stream of read responses containing events from the stream.
    /// - Throws: `KurrentError` if the read operation fails.
    public func read(configure: @Sendable (inout Read.Options) -> Void = { _ in }) async throws(KurrentError) -> AsyncThrowingStream<Read.Response, Error> {
        var options = Read.Options()
        configure(&options)
        let usecase = Read(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Subscribes to events from the specified stream.
    ///
    /// - Parameter configure: A closure to configure subscription options. Defaults to no-op.
    /// - Returns: A subscription to the stream's events.
    /// - Throws: `KurrentError` if the subscription fails.
    public func subscribe(configure: @Sendable (inout Subscribe.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription {
        var options = Subscribe.Options()
        configure(&options)
        let usecase = Subscribe(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Deletes the specified stream.
    ///
    /// - Parameter configure: A closure to configure delete options. Defaults to no-op.
    /// - Returns: A `Delete.Response` indicating the result of the operation.
    /// - Throws: An error if the delete operation fails.
    @discardableResult
    public func delete(configure: @Sendable (inout Delete.Options) -> Void = { _ in }) async throws(KurrentError) -> Delete.Response {
        var options = Delete.Options()
        configure(&options)
        let usecase = Delete(to: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Marks the specified stream as permanently deleted (tombstoned).
    ///
    /// - Parameter configure: A closure to configure tombstone options. Defaults to no-op.
    /// - Returns: A `Tombstone.Response` indicating the result of the operation.
    /// - Throws: An error if the tombstone operation fails.
    @discardableResult
    public func tombstone(configure: @Sendable (inout Tombstone.Options) -> Void = { _ in }) async throws(KurrentError) -> Tombstone.Response {
        var options = Tombstone.Options()
        configure(&options)
        let usecase = Tombstone(to: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
