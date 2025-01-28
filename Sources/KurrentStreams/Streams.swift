//
//  Streams.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/17.
//

@_exported
import KurrentCore

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct Streams: GRPCConcreteService {
    package typealias Client = EventStore_Client_Streams_Streams.Client<HTTP2ClientTransport.Posix>

    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    public init(settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Streams {
    @discardableResult
    public func setMetadata(to identifier: StreamIdentifier, metadata: StreamMetadata, options: Append.Options = .init()) async throws -> Append.Response {
        try await append(
            to: .init(name: "$$\(identifier.name)"),
            events: [
                .init(
                    eventType: "$metadata",
                    payload: metadata
                ),
            ],
            options: options
        )
    }

    @discardableResult
    public func getMetadata(on identifier: StreamIdentifier, cursor: Cursor<CursorPointer> = .end) async throws -> StreamMetadata? {
        let responses = try await read(
            .init(name: "$$\(identifier.name)"),
            cursor: cursor, options: .init()
        )
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
                    try JSONDecoder().decode(StreamMetadata.self, from: readEvent.recordedEvent.data)
                default:
                    throw ClientError.eventDataError(message: "The data of event could not be parsed. ContentType of Stream Metadata should be encoded in .json format.")
                }
            default:
                throw ClientError.readResponseError(message: "The metadata event is not exist.")
            }
        }
    }

    public func append(to streamIdentifier: StreamIdentifier, events: [EventData], options: Append.Options = .init()) async throws -> Append.Response {
        let usecase = Append(to: streamIdentifier, events: events, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func read(_ streamIdentifier: StreamIdentifier, cursor: Cursor<CursorPointer>, options: Read.Options = .init()) async throws -> AsyncThrowingStream<Read.Response, Error> {
        let usecase = Read(streamIdentifier: streamIdentifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func readAll(cursor: Cursor<ReadAll.CursorPointer>, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        let usecase = ReadAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func subscribe(_ streamIdentifier: StreamIdentifier, cursor: Cursor<StreamRevision>, options: Subscribe.Options = .init()) async throws -> Subscription {
        let usecase = Subscribe(streamIdentifier: streamIdentifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func subscribeToAll(cursor: Cursor<StreamPosition>, options: SubscribeToAll.Options = .init()) async throws -> Subscription {
        let usecase = SubscribeToAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    @discardableResult
    public func delete(_ streamIdentifier: StreamIdentifier, options: Delete.Options = .init()) async throws -> Delete.Response {
        let usecase = Delete(streamIdentifier: streamIdentifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    @discardableResult
    public func tombstone(_ streamIdentifier: StreamIdentifier, options: Tombstone.Options = .init()) async throws -> Tombstone.Response {
        let usecase = Tombstone(streamIdentifier: streamIdentifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

// MARK: - Convenience Method

extension Streams {
    public func readAll(from position: StreamPosition, directTo direction: Direction, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        try await readAll(cursor: .specified(.init(position: position, direction: direction)), options: options)
    }
}
