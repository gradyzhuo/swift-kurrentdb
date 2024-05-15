//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/18.
//

import Foundation
import GRPC
import GRPCSupport

public struct EventStoreDBClient {
    
    internal var channel: GRPCChannel {
        get throws {
            return try GRPCChannelPool.with(settings: settings)
        }
    }
    
    public var defaultCallOptions: CallOptions
    
    public private(set) var settings: ClientSettings
    
    public init(settings: ClientSettings = EventStore.shared.settings, defaultCallOptions: CallOptions? = nil) throws {
        self.defaultCallOptions = try defaultCallOptions ?? settings.makeCallOptions()
        self.settings = settings
    }
    
}


//MARK: - Streams Operations

extension EventStoreDBClient{
    public func setMetadata(streamName: String, metadata: Stream.Metadata, configure: (_ options: FluentInterface<StreamClient.Append.Options>) -> FluentInterface<StreamClient.Append.Options>) async throws -> StreamClient.Append.Response.Success{
        return try await appendTo(
            streamName: "$$\(streamName)",
            events: .init(
                eventType: "$metadata",
                payload: metadata
            ),
            configure: configure
        )
        
    }
    
    public func getMetadata(streamName: String, cursor: Cursor<StreamClient.Read.CursorPointer> = .end) async throws -> Stream.Metadata?{
        let responses = try read(streamName: "$$\(streamName)", cursor: cursor) { $0 }
        return try await responses.first {
            switch $0.content {
            case .event(_):
                true
            default:
                false
            }
        }.flatMap{
            switch $0.content {
            case .event(let readEvent):
                switch readEvent.recordedEvent.contentType {
                case .json:
                    try JSONDecoder().decode(Stream.Metadata.self, from: readEvent.recordedEvent.data)
                default:
                    throw ClientError.eventDataError(message: "The data of event could not be parsed. ContentType of Stream Metadata should be encoded in .json format.")
                }
            case .streamNotFound(let metaStreamName):
                throw ClientError.streamNameError(message: "The stream name of metadata not found: \(metaStreamName).")
            default:
                throw ClientError.readResponseError(message: "The metadata event is not exist.")
            }
        }
    }
    
    // MARK: Append methods -
    public func appendTo(streamName: String, events: [EventData], configure: (_ options: FluentInterface<StreamClient.Append.Options>) -> FluentInterface<StreamClient.Append.Options>) async throws -> StreamClient.Append.Response.Success {
        
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)
        let options = configure(.init(subject: .init()))
        
        return try await client.appendTo(stream: .init(name: streamName), events: events, options: options.subject)

    }

    public func appendTo(streamName: String, events: EventData ..., configure: (_ options: FluentInterface<StreamClient.Append.Options>) -> FluentInterface<StreamClient.Append.Options> = { $0 }) async throws -> StreamClient.Append.Response.Success {
        
        return try await appendTo(streamName: streamName, events: events, configure: configure)
        
    }

    // MARK: Read by all streams methods -

    public func readAllStreams(cursor: Cursor<StreamClient.ReadAll.CursorPointer>, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)
        
        let options = configure(.init())
        return try client.readAll(cursor: cursor, options: options, channel: channel, callOptions: defaultCallOptions)
        
    }


    // MARK: Read by a stream methos -

    public func read(streamName: String, cursor: Cursor<StreamClient.Read.CursorPointer>, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)
        
        let options = configure(.init())
        return try client.read(stream: .init(name: streamName), cursor: cursor, options: options)
        
    }

    public func read(streamName: String, at revision: UInt64, direction: StreamClient.Read.Direction = .forward, configure: (_ options: StreamClient.Read.Options) -> StreamClient.Read.Options = { $0 }) throws -> StreamClient.Read.Responses {
        
        let cursor:Cursor<StreamClient.Read.CursorPointer> = .specified(.init(revision: revision, direction: direction))
        return try read(streamName: streamName, cursor: cursor, configure: configure)
        
    }
    
//    public func subscribeToStream(streamName: String){
//        let options = StreamClient.Read.Options()
//    }
    

    // MARK: (Soft) Delete a stream -

    @discardableResult
    public func delete(streamName: String, configure: (_ options: StreamClient.Delete.Options) -> StreamClient.Delete.Options) async throws -> StreamClient.Delete.Response {
        
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)
        
        let options = configure(.init())
        return try await client.delete(identifier: .init(name: streamName), options: options, channel: channel, callOptions: defaultCallOptions)
    }

    // MARK: (Hard) Delete a stream -

    @discardableResult
    public func tombstone(streamName: String, configure: (_ options: StreamClient.Tombstone.Options) -> StreamClient.Tombstone.Options) async throws -> StreamClient.Tombstone.Response {
        
        let client = try StreamClient(channel: channel, callOptions: defaultCallOptions)
        
        let options = configure(.init())
        return try await client.tombstone(identifier: .init(name: streamName), options: options, channel: channel, callOptions: defaultCallOptions)
        
    }
}


//MARK: - Operations
extension EventStoreDBClient {
    
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> OperationsClient.ScavengeResponse {
        let client = try OperationsClient(channel: channel, callOptions: defaultCallOptions)
        return try await client.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }
    
}


extension EventStoreDBClient {
    public func createPersistentSubscription(streamName: String, groupName: String, options: PersistentSubscriptionsClient.Create.ToStream.Options = .init()) async throws{
        
        let underlyingClient = try PersistentSubscriptionsClient.UnderlyingClient.init(channel: channel, defaultCallOptions: defaultCallOptions)
        let handler: PersistentSubscriptionsClient.Create.ToStream = .init(streamIdentifier: .init(name: streamName), groupName: groupName, options: options)
        
        let request = try handler.build()

        try await handler.handle(response: underlyingClient.create(request))
    }
    
    public func createPersistentSubscriptionToAll(groupName: String, options: PersistentSubscriptionsClient.Create.ToAll.Options = .init()) async throws {
        let underlyingClient = try PersistentSubscriptionsClient.UnderlyingClient.init(channel: channel, defaultCallOptions: defaultCallOptions)
        let handler: PersistentSubscriptionsClient.Create.ToAll = .init(groupName: groupName, options: options)
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.create(request))
        
    }

    
    // MARK: - Restart Subsystem Action

    public func restartPersistentSubscriptionSubsystem(settings: ClientSettings = EventStore.shared.settings) async throws {
        let client = try PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        return try await client.restartSubsystem()
    }
    
    
    // MARK: -
    
    public func subscribePersistentSubscriptionTo(_ streamSelection:Selector<Stream.Identifier>, groupName: String, configure: (_ options: PersistentSubscriptionsClient.Read.Options)->PersistentSubscriptionsClient.Read.Options = { $0 } ) async throws -> PersistentSubscriptionsClient.Subscription {
        
        
        let client = try PersistentSubscriptionsClient(channel: channel, callOptions: defaultCallOptions)
        
        let options = PersistentSubscriptionsClient.Read.Options().set(bufferSize: 1000)
            .set(uuidOption: .string)
        return try await client.subscribeTo(streamSelection, groupName: groupName, options: options)

    }
    
}
