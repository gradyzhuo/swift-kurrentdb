//
//  Streams+SpecifiedStreamTarget.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/26.
//

import Foundation

// MARK: - Specified Stream Operations

/// Operations available when the target identifies a single named stream.
extension Streams where Target: SpecifiedStreamTarget {
    /// Identifier of the target stream.
    public var identifier: StreamIdentifier {
        target.identifier
    }

    /// Sets metadata on the specified stream.
    ///
    /// - Parameters:
    ///   - metadata: The ``StreamMetadata`` to store.
    ///   - expectedRevision: The revision expected at the metadata stream before writing. Defaults to `.any`.
    /// - Returns: An `Append.Response` containing the result of the metadata write.
    /// - Throws: `KurrentError` if the write fails or a revision conflict occurs.
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

    /// Retrieves the latest metadata for the stream.
    ///
    /// - Returns: The decoded ``StreamMetadata``, or `nil` if no metadata event has been written.
    /// - Throws: `KurrentError` if the metadata event is not JSON-encoded or a client error occurs.
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

    /// Appends events to the stream.
    ///
    /// ```swift
    /// try await client.streams(specified: "orders").append(events: [event]) {
    ///     $0.expectedRevision = .streamExists
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - events: Events to append.
    ///   - configure: Closure to configure ``Append/Options`` (e.g., expected revision). Defaults to no-op.
    /// - Returns: An `Append.Response` with the server-assigned positions.
    /// - Throws: `KurrentError` if the append fails or a revision conflict occurs.
    @discardableResult
    public func append(events: [EventData], configure: @Sendable (inout Append.Options) -> Void = { _ in }) async throws(KurrentError) -> Append.Response {
        var options = Append.Options()
        configure(&options)
        let usecase = Append(to: identifier, events: events, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Appends a variadic list of events to the stream.
    ///
    /// - Parameters:
    ///   - events: One or more events to append.
    ///   - configure: Closure to configure ``Append/Options``. Defaults to no-op.
    /// - Returns: An `Append.Response` with the server-assigned positions.
    /// - Throws: `KurrentError` if the append fails or a revision conflict occurs.
    @discardableResult
    public func append(events: EventData..., configure: @Sendable (inout Append.Options) -> Void = { _ in }) async throws(KurrentError) -> Append.Response {
        try await append(events: events, configure: configure)
    }

    /// Reads events from the stream.
    ///
    /// ```swift
    /// let responses = try await client.streams(specified: "orders").read {
    ///     $0.direction = .backward
    ///     $0.limit = 10
    /// }
    /// for try await response in responses {
    ///     let event = try response.event
    /// }
    /// ```
    ///
    /// - Parameter configure: Closure to configure ``Read/Options`` (direction, limit, starting revision). Defaults to no-op.
    /// - Returns: An async throwing stream of ``Streams/ReadResponse`` values.
    /// - Throws: `KurrentError` if the stream is not found or the read fails.
    public func read(configure: @Sendable (inout Read.Options) -> Void = { _ in }) async throws(KurrentError) -> AsyncThrowingStream<Read.Response, Error> {
        var options = Read.Options()
        configure(&options)
        let usecase = Read(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Subscribes to live events from the stream.
    ///
    /// - Parameter configure: Closure to configure ``Subscribe/Options`` (starting position, filter). Defaults to no-op.
    /// - Returns: A ``Streams/Subscription`` that delivers events as they are appended.
    /// - Throws: `KurrentError` if the subscription cannot be established.
    public func subscribe(configure: @Sendable (inout Subscribe.Options) -> Void = { _ in }) async throws(KurrentError) -> Subscription {
        var options = Subscribe.Options()
        configure(&options)
        let usecase = Subscribe(from: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Soft-deletes the stream, allowing it to be recreated by appending new events.
    ///
    /// - Parameter configure: Closure to configure ``Delete/Options`` (expected revision). Defaults to no-op.
    /// - Returns: A `Delete.Response` with the resulting stream position.
    /// - Throws: `KurrentError` if the delete fails or a revision conflict occurs.
    @discardableResult
    public func delete(configure: @Sendable (inout Delete.Options) -> Void = { _ in }) async throws(KurrentError) -> Delete.Response {
        var options = Delete.Options()
        configure(&options)
        let usecase = Delete(to: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Permanently tombstones the stream so it cannot be recreated.
    ///
    /// - Parameter configure: Closure to configure ``Tombstone/Options`` (expected revision). Defaults to no-op.
    /// - Returns: A `Tombstone.Response` with the resulting stream position.
    /// - Throws: `KurrentError` if the tombstone operation fails or a revision conflict occurs.
    @discardableResult
    public func tombstone(configure: @Sendable (inout Tombstone.Options) -> Void = { _ in }) async throws(KurrentError) -> Tombstone.Response {
        var options = Tombstone.Options()
        configure(&options)
        let usecase = Tombstone(to: identifier, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}
