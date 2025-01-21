//
//  StreamClient.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCEncapsulates
import KurrentCore

public typealias UnderlyingService = EventStore_Client_Streams_Streams

public struct Service: GRPCConcreteClient {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias UnderlyingClient = UnderlyingService.Client<Transport>
    
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults){
        self.settings = settings
        self.callOptions = callOptions
    }
}


extension Service {
    
    @discardableResult
    public func setMetadata(to identifier: KurrentCore.Stream.Identifier, metadata: KurrentCore.Stream.Metadata, options: Append.Options = .init()) async throws -> Append.Response.Success {
        
        try await append(
            to: .init(name: "$$\(identifier.name)"),
            events: [
                .init(
                eventType: "$metadata",
                payload: metadata)
            ],
            options: options
        )
    }
    
    @discardableResult
    public func getMetadata(on identifier: KurrentCore.Stream.Identifier, cursor: Cursor<ReadCursorPointer> = .end) async throws -> KurrentCore.Stream.Metadata? {
        
        let responses = try await read(
            .init(name: "$$\(identifier.name)"),
            cursor: cursor, options: .init())
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
                    try JSONDecoder().decode(Stream.Metadata.self, from: readEvent.recordedEvent.data)
                default:
                    throw ClientError.eventDataError(message: "The data of event could not be parsed. ContentType of Stream Metadata should be encoded in .json format.")
                }
            default:
                throw ClientError.readResponseError(message: "The metadata event is not exist.")
            }
        }
    }
    
    package func append(to streamIdentifier: KurrentCore.Stream.Identifier, events: [EventData], options: Append.Options = .init()) async throws -> Append.Response.Success{
        let usecase = Append(to: streamIdentifier, events: events, options: options)
        let response = try await usecase.perform(settings: settings, callOptions: callOptions)
        return switch response {
        case let .success(successResult):
            successResult
        case let .wrong(wrongResult):
            throw wrongResult
        }
    }
    
    package func read(_ streamIdentifier: KurrentCore.Stream.Identifier, cursor: Cursor<ReadCursorPointer>, options: Read.Options = .init()) async throws -> AsyncThrowingStream<Read.Response, Error> {
        let usecase = Read(streamIdentifier: streamIdentifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    package func readAll(cursor: Cursor<ReadAll.CursorPointer>, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        let usecase = ReadAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    package func subscribe(_ streamIdentifier: KurrentCore.Stream.Identifier, cursor: Cursor<KurrentCore.Stream.Revision>, options: Subscribe.Options = .init()) async throws -> Subscription {
        let usecase = Subscribe(streamIdentifier: streamIdentifier, cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    package func subscribeToAll(cursor: Cursor<KurrentCore.Stream.Position>, options: SubscribeToAll.Options = .init()) async throws -> Subscription {
        let usecase = SubscribeToAll(cursor: cursor, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    @discardableResult
    package func delete(_ streamIdentifier: KurrentCore.Stream.Identifier, options: Delete.Options = .init()) async throws -> Delete.Response {
        let usecase = Delete(streamIdentifier: streamIdentifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    @discardableResult
    package func tombstone(_ streamIdentifier: KurrentCore.Stream.Identifier, options: Tombstone.Options = .init()) async throws -> Tombstone.Response {
        let usecase = Tombstone(streamIdentifier: streamIdentifier, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

//MARK: - Convenience Method
extension Service {
    
    package func readAll(from position: KurrentCore.Stream.Position, directTo direction: KurrentCore.Stream.Direction, options: ReadAll.Options = .init()) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        return try await readAll(cursor: .specified(.init(position: position, direction: direction)), options: options)
    }
    
}


