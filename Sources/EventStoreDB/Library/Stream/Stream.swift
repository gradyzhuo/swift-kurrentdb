//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation
import GRPC

@available(macOS 10.15, iOS 13, *)
public struct Stream {
    
    internal typealias UnderlyingClient = EventStore_Client_Streams_StreamsAsyncClient
    
    public static var defaultCallOptions: GRPC.CallOptions = .init()
    
    public var callOptions: GRPC.CallOptions{
        get{
            underlyingClient.defaultCallOptions
        }
        set{
            underlyingClient.defaultCallOptions = newValue
        }
    }
    
    public internal(set) var identifier: Stream.Identifier
    internal var underlyingClient: UnderlyingClient
    
    @available(macOS 13.0, *)
    public init(identifier: Stream.Identifier, channel: GRPCChannel? = nil) throws {
        let channel = channel ?? EventStore.shared.channel

        self.identifier = identifier
        self.underlyingClient = UnderlyingClient.init(channel: channel)
        
    }
    
}

@available(macOS 10.15, *)
extension Stream {
    
    //MARK: - Append methods
    public func append(event: EventData, options: Append.Options = .init()) async throws -> Append.Response.Success {
        
        let handler: Append = .init(streamIdentifier: self.identifier, event: event, options: options)
        
        let requests = try handler.build()
        let response = try await handler.handle(response: underlyingClient.append(requests))
        
        return switch response {
        case .success(let successResult):
            successResult
        case .wrong(let wrongResult):
            throw wrongResult
        }
    }
    
    public func append(event: EventData, configure: (_ options: Append.Options)->Append.Options = { $0 }) async throws -> Append.Response.Success {
       
        let options = configure(.init())
        return try await self.append(event: event, options: options)
        
    }
    
    public func append(id: UUID, type: String, data: Data, configure: (_ options: Append.Options)->Append.Options = { $0 }) async throws -> Append.Response.Success {
        
        let event: EventData = .init(id: id, type: type, content: .data(data))
        let options = configure(.init())
        return try await self.append(event: event, options: options)
        
    }
    
    public func append(id: UUID, type: String, content: Codable, configure: (_ options: Append.Options)->Append.Options = { $0 }) async throws -> Append.Response.Success {
        
        let event: EventData = .init(id: id, type: type, content: .codable(content))
        let options = configure(.init())
        return try await self.append(event: event, options: options)
        
    }
    
    //MARK: - Read by all streams methos
    @available(macOS 13.0, *)
    public static func readAll(cursor: Read.Cursor<Read.Position>, options: Stream.Read.Options = .init(), settings: ClientSettings = EventStore.shared.settings ) throws -> Read.Responses{
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let underlyingClient = UnderlyingClient.init(channel: channel)

        let handler = ReadAll(cursor: cursor, options: options)
        
        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.read(request))
        
    }
    
    @available(macOS 13.0, *)
    public static func readAll(cursor: Read.Cursor<Read.Position>, settings: ClientSettings = EventStore.shared.settings, configure: (_ options: Stream.Read.Options) -> Stream.Read.Options = { $0 } ) throws -> Read.Responses{
        
        let options = configure(.init())
        return try Stream.readAll(cursor: cursor, options: options, settings: settings)
    }
    
    
    //MARK: - Read by a stream methos
    public func read(cursor: Read.Cursor<UInt64>, options: Stream.Read.Options = .init()) throws -> Read.Responses{
        
        
        let handler = Read(streamIdentifier: self.identifier, cursor: cursor, options: options)
        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.read(request))
    }
    
    public func read(at revision: UInt64, direction: Read.Direction = .forward, options: Stream.Read.Options = .init()) throws -> Read.Responses{
        
        let handler = Read(streamIdentifier: self.identifier, cursor: .at(revision, direction: direction), options: options)
        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.read(request))
    }
    
    public func read(cursor: Read.Cursor<UInt64>, configure: (_ options: Stream.Read.Options) -> Stream.Read.Options = { $0 } ) throws -> Read.Responses{
        
        let options = configure(.init())
        return try self.read(cursor: cursor, options: options)
        
    }
    
    public func read(at revision: UInt64, direction: Read.Direction = .forward, configure: (_ options: Stream.Read.Options) -> Stream.Read.Options = { $0 } ) throws -> Read.Responses{
        
        let options = configure(.init())
        return try self.read(cursor: .at(revision, direction: direction), options: options)
        
    }
    
    //MARK: - (Soft) Delete a stream
    
    @available(macOS 13.0, *)
    @discardableResult
    public static func delete(identifier: Stream.Identifier, options: Delete.Options, settings: ClientSettings = EventStore.shared.settings) async throws -> Delete.Response {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let underlyingClient = Stream.UnderlyingClient(channel: channel)
        
        
        let handler = Delete(streamIdentifier: identifier, options: options)
        
        let request = try handler.build()
        return try await handler.handle(response: underlyingClient.delete(request))
    }
    
    
    @available(macOS 13.0, *)
    @discardableResult
    public static func delete(identifier: Stream.Identifier, expected expectedRevision: Stream.Revision<Stream.Delete.Options.UnderlyingMessage.OneOf_ExpectedStreamRevision>, settings: ClientSettings = EventStore.shared.settings) async throws -> Delete.Response {
        
        let options = Stream.Delete.Options()
        options.expected(revision: expectedRevision)
        
        return try await Stream.delete(identifier: identifier, options: options, settings: settings)
    }
    
    @available(macOS 13.0, *)
    @discardableResult
    public static func delete(identifier: Stream.Identifier, settings: ClientSettings = EventStore.shared.settings, configure: (_ options: Delete.Options)->Delete.Options = { $0 }) async throws -> Delete.Response {
        
        let options = configure(.init())
        return try await Stream.delete(identifier: identifier, options: options, settings: settings)
    }
    
    //MARK: - (Hard) Delete a stream
    
    @available(macOS 13.0, *)
    @discardableResult
    public static func tombstone(identifier: Stream.Identifier, options : Tombstone.Options, settings: ClientSettings = EventStore.shared.settings) async throws -> Tombstone.Response {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let underlyingClient = Stream.UnderlyingClient(channel: channel)
        
        
        let handler = Tombstone(streamIdentifier: identifier, options: options)
        let request = try handler.build()
        return try await handler.handle(response: underlyingClient.tombstone(request))
    
    }
    
    
    @available(macOS 13.0, *)
    @discardableResult
    public static func tombstone(identifier: Stream.Identifier, expected expectedRevision: Stream.Revision<Tombstone.Options.UnderlyingMessage.OneOf_ExpectedStreamRevision>, settings: ClientSettings = EventStore.shared.settings) async throws -> Tombstone.Response {
        
        let options = Stream.Tombstone.Options()
        options.expected(revision: expectedRevision)
        
        return try await Stream.tombstone(identifier: identifier, options: options, settings: settings)
    }
    
    @available(macOS 13.0, *)
    @discardableResult
    public func tombstone(identifier: Stream.Identifier, settings: ClientSettings = EventStore.shared.settings, configure: (_ options: Tombstone.Options)->Tombstone.Options = { $0 }) async throws -> Tombstone.Response {
       
        let options = configure(.init())
        return try await Stream.tombstone(identifier: identifier, options: options, settings: settings)
        
    }
    
}
