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

public struct Streams<Target: StreamTarget>: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_Streams_Streams.Client<HTTP2ClientTransport.Posix>

    public let settings: ClientSettings
    public let callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup
    public let target: Target

    public init(stream target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Streams where Target == SpecifiedStream {
    public var identifier: StreamIdentifier {
        get{
            target.identifier
        }
    }
    
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

    @discardableResult
    public func getMetadata(cursor: Cursor<CursorPointer> = .end) async throws -> StreamMetadata? {
        let usecase = Read(from: .init(name: "$$\(identifier.name)"), cursor: cursor, options: .init())
        let responses = try await usecase.perform(settings: settings, callOptions: callOptions)
        
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

    public func append(events: [EventData], options: Append.Options = .init()) async throws -> Append.Response {
        let usecase = Append(to: identifier, events: events, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func read(cursor: Cursor<CursorPointer>, options: Read.Options = .init()) async throws -> AsyncThrowingStream<Read.Response, Error> {
        let usecase = Read(from: identifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func subscribe(cursor: Cursor<StreamRevision>, options: Subscribe.Options = .init()) async throws -> Subscription {
        let usecase = Subscribe(from: identifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    @discardableResult
    public func delete(options: Delete.Options = .init()) async throws -> Delete.Response {
        let usecase = Delete(to: identifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    @discardableResult
    public func tombstone(options: Tombstone.Options = .init()) async throws -> Tombstone.Response {
        let usecase = Tombstone(to: identifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

//MARK: - All
extension Streams where Target == AllStreams {
    public func read(cursor: Cursor<ReadAll.CursorPointer>, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        let usecase = ReadAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func read(from position: StreamPosition, directTo direction: Direction, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        try await read(cursor: .specified(.init(position: position, direction: direction)), options: options)
    }
    
    public func subscribe(cursor: Cursor<StreamPosition>, options: SubscribeAll.Options = .init()) async throws -> Streams.Subscription {
        let usecase = SubscribeAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
}
