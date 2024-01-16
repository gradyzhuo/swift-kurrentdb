//
//  StreamClient.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPC
import GRPCSupport

public struct StreamClient: EventStoreClient {
    public typealias UnderlyingClient = EventStore_Client_Streams_StreamsAsyncClient

    public internal(set) var identifier: StreamClient.Identifier
    public var clientSettings: ClientSettings
    public var channel: GRPCChannel

    public init(identifier: StreamClient.Identifier, settings: ClientSettings = EventStoreDB.shared.settings) throws {
        clientSettings = settings
        channel = try GRPCChannelPool.with(settings: clientSettings)
        self.identifier = identifier
    }

    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        .init(channel: channel, defaultCallOptions: callOptions)
    }
}

extension StreamClient {
    public enum Cursor<Pointer> {
        case start
        case end
        case at(Pointer)
    }
}

extension StreamClient {
    // MARK: - Append methods

    public func append(events: [EventData], options: Append.Options = .init()) async throws -> Append.Response.Success {
        let handler: Append = .init(streamIdentifier: identifier, events: events, options: options)

        let requests = try handler.build()
        let response = try await handler.handle(response: underlyingClient.append(requests))

        return switch response {
        case let .success(successResult):
            successResult
        case let .wrong(wrongResult):
            throw wrongResult
        }
    }

    public func append(events: EventData ..., configure: (_ options: FluentInterface<Append.Options>) -> FluentInterface<Append.Options>) async throws -> Append.Response.Success {
        let options = configure(.init(subject: .init()))
        return try await append(events: events, options: options.subject)
    }

    public func append(events: [EventData], configure: (_ options: FluentInterface<Append.Options>) -> FluentInterface<Append.Options>) async throws -> Append.Response.Success {
        let options = configure(.init(subject: .init()))
        return try await append(events: events, options: options.subject)
    }

    public func append(id: UUID, eventType: String, data: Data, configure: (_ options: FluentInterface<Append.Options>) -> FluentInterface<Append.Options>) async throws -> Append.Response.Success {
        let event: EventData = .init(id: id, eventType: eventType, data: data, contentType: .binary)

        let options = configure(.init(subject: .init()))
        return try await append(events: [event], options: options.subject)
    }

    public func append(id: UUID, eventType: String, content: Codable, configure: (_ options: FluentInterface<Append.Options>) -> FluentInterface<Append.Options>) async throws -> Append.Response.Success {
        let event: EventData = try .init(id: id, eventType: eventType, content: content)
        let options = configure(.init(subject: .init()))
        return try await append(events: [event], options: options.subject)
    }

    // MARK: - Read by all streams methos

    public static func readAll(cursor: StreamClient.Cursor<ReadAll.CursorPointer>, options: StreamClient.Read.Options = .init(), settings: ClientSettings = EventStoreDB.shared.settings) throws -> Read.Responses {
        let channel = try GRPCChannelPool.with(settings: settings)
        var underlyingClient: UnderlyingClient = .init(channel: channel)

        try underlyingClient.configure(by: settings)

        let handler = ReadAll(cursor: cursor, options: options)

        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.read(request))
    }

    public static func readAll(cursor: StreamClient.Cursor<ReadAll.CursorPointer>, settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options) throws -> Read.Responses {
        let options = configure(.init())
        return try StreamClient.readAll(cursor: cursor, options: options, settings: settings)
    }

    // MARK: - Read by a stream methos

    public func read(cursor: StreamClient.Cursor<Read.CursorPointer>, options: StreamClient.Read.Options = .init()) throws -> Read.Responses {
        let handler = Read(streamIdentifier: identifier, cursor: cursor, options: options)
        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.read(request))
    }

    public func read(at revision: UInt64, direction: Read.Direction = .forward, options: StreamClient.Read.Options = .init()) throws -> Read.Responses {
        let handler = Read(streamIdentifier: identifier, cursor: .at(.init(revision: revision, direction: direction)), options: options)
        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.read(request))
    }

    public func read(cursor: StreamClient.Cursor<Read.CursorPointer>, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options) throws -> Read.Responses {
        let options = configure(.init())
        return try read(cursor: cursor, options: options)
    }

    public func read(at revision: UInt64, direction: Read.Direction = .forward, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options) throws -> Read.Responses {
        let options = configure(.init())
        return try read(cursor: .at(.init(revision: revision, direction: direction)), options: options)
    }

    // MARK: - (Soft) Delete a stream

    @discardableResult
    public static func delete(identifier: StreamClient.Identifier, options: Delete.Options, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Delete.Response {
        let channel = try GRPCChannelPool.with(settings: settings)
        var underlyingClient = StreamClient.UnderlyingClient(channel: channel)
        try underlyingClient.configure(by: settings)

        let handler = Delete(streamIdentifier: identifier, options: options)

        // build request
        let request = try handler.build()
        // handle response
        return try await handler.handle(response: underlyingClient.delete(request))
    }

    @discardableResult
    public static func delete(identifier: StreamClient.Identifier, expected expectedRevision: StreamClient.Revision, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Delete.Response {
        let options = StreamClient.Delete.Options()
        options.expected(revision: expectedRevision)

        return try await StreamClient.delete(identifier: identifier, options: options, settings: settings)
    }

    @discardableResult
    public static func delete(identifier: StreamClient.Identifier, settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: Delete.Options) -> Delete.Options) async throws -> Delete.Response {
        let options = configure(.init())
        return try await StreamClient.delete(identifier: identifier, options: options, settings: settings)
    }

    // MARK: - (Hard) Delete a stream

    @discardableResult
    public static func tombstone(identifier: StreamClient.Identifier, options: Tombstone.Options, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Tombstone.Response {
        let channel = try GRPCChannelPool.with(settings: settings)
        var underlyingClient = StreamClient.UnderlyingClient(channel: channel)
        try underlyingClient.configure(by: settings)

        let handler = Tombstone(streamIdentifier: identifier, options: options)
        let request = try handler.build()
        return try await handler.handle(response: underlyingClient.tombstone(request))
    }

    @discardableResult
    public static func tombstone(identifier: StreamClient.Identifier, expected expectedRevision: StreamClient.Revision, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Tombstone.Response {
        let options = StreamClient.Tombstone.Options()
        options.expected(revision: expectedRevision)

        return try await StreamClient.tombstone(identifier: identifier, options: options, settings: settings)
    }

    @discardableResult
    public func tombstone(identifier: StreamClient.Identifier, settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: Tombstone.Options) -> Tombstone.Options) async throws -> Tombstone.Response {
        let options = configure(.init())
        return try await StreamClient.tombstone(identifier: identifier, options: options, settings: settings)
    }
}
