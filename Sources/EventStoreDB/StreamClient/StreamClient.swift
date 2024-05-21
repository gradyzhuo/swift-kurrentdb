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

extension StreamClient {
    public class FilterOption {
        public enum Window {
            case count
            case max(UInt32)
        }

        public enum FilterType {
            case streamName(regex: String)
            case eventType(regex: String)
        }

        public internal(set) var type: FilterType
        public internal(set) var window: Window
        public internal(set) var prefixes: [String]
        public internal(set) var checkpointIntervalMultiplier: UInt32

        required init(type: FilterType, window: Window = .count, prefixes: [String] = []) {
            self.type = type
            self.window = window
            self.prefixes = prefixes
            checkpointIntervalMultiplier = .max
        }

        @discardableResult
        public static func onStreamName(regex: String) -> Self {
            .init(type: .streamName(regex: regex))
        }

        @discardableResult
        public static func onEventType(regex: String) -> Self {
            .init(type: .eventType(regex: regex))
        }

        @discardableResult
        public func set(max maxCount: UInt32) -> Self {
            window = .max(maxCount)
            return self
        }

        @discardableResult
        public func set(checkpointIntervalMultiplier multiplier: UInt32) -> Self {
            checkpointIntervalMultiplier = multiplier
            return self
        }

        @discardableResult
        public func add(prefix: String) -> Self {
            prefixes.append(prefix)
            return self
        }
    }
}
