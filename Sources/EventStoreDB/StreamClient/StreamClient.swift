//
//  StreamClient.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPC
import GRPCEncapsulates

public struct StreamClient: GRPCConcreteClient {
    package typealias UnderlyingClient = EventStore_Client_Streams_StreamsAsyncClient

    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions
    
    public init(channel: GRPCChannel, callOptions: CallOptions) {
        self.channel = channel
        self.callOptions = callOptions
    }
}

extension StreamClient {
    // MARK: - Append methods

    public func appendTo(stream: Stream.Identifier, events: [EventData], options: Append.Options) async throws -> Append.Response.Success {
        let handler: Append = .init(streamIdentifier: stream, events: events, options: options)
        let requests = try handler.build()
        let response = try await handler.handle(response: underlyingClient.append(requests))

        return switch response {
        case let .success(successResult):
            successResult
        case let .wrong(wrongResult):
            throw wrongResult
        }
    }

    // MARK: - Read by all streams methos

    package func readAll(cursor: Cursor<ReadAll.CursorPointer>, options: StreamClient.Read.Options = .init(), channel _: GRPCChannel, callOptions _: CallOptions) throws -> Read.Responses {
        let handler = ReadAll(cursor: cursor, options: options)

        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.read(request))
    }

    // MARK: - Read by a stream methos

    package func read(stream: Stream.Identifier, cursor: Cursor<Read.CursorPointer>, options: StreamClient.Read.Options) throws -> Read.Responses {
        let handler = Read(streamIdentifier: stream, cursor: cursor, options: options)
        let request = try handler.build()

        return try handler.handle(responses: underlyingClient.read(request))
    }

    // MARK: - Read by a stream methos

    package func subscribe(stream: Stream.Identifier, from cursor: Cursor<Stream.Revision>, options: StreamClient.Subscribe.Options) async throws -> Subscription {
        let handler = Subscribe(streamIdentifier: stream, cursor: cursor, options: options)
        let request = try handler.build()

        let getSubscriptionCall = underlyingClient.makeReadCall(request)
        return try await .init(readCall: getSubscriptionCall)
    }

    // MARK: - Read by a stream methos

    package func subscribeToAll(from cursor: Cursor<Stream.Position>, options: StreamClient.SubscribeToAll.Options) async throws -> Subscription {
        let handler = SubscribeToAll(cursor: cursor, options: options)
        let request = try handler.build()

        let getSubscriptionCall = underlyingClient.makeReadCall(request)
        return try await .init(readCall: getSubscriptionCall)
    }

    // MARK: - (Soft) Delete a stream

    @discardableResult
    public func delete(identifier: Stream.Identifier, options: Delete.Options, channel _: GRPCChannel, callOptions _: CallOptions) async throws -> Delete.Response {
        let handler = Delete(streamIdentifier: identifier, options: options)

        // build request
        let request = try handler.build()
        // handle response
        return try await handler.handle(response: underlyingClient.delete(request))
    }

    // MARK: - (Hard) Delete a stream

    @discardableResult
    public func tombstone(identifier: Stream.Identifier, options: Tombstone.Options, channel _: GRPCChannel, callOptions _: CallOptions) async throws -> Tombstone.Response {
        let handler = Tombstone(streamIdentifier: identifier, options: options)
        let request = try handler.build()
        return try await handler.handle(response: underlyingClient.tombstone(request))
    }
}
