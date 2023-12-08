//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import GRPC


@available(macOS 10.15, *)
public struct PersistentSubscriptions: _GRPCClient {
    
    typealias UnderlyingClient = EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient
    
    var clientSettings: ClientSettings
    var streamSelection: StreamSelection
    var underlyingClient: EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient
    
    public init(selection: StreamSelection, settings: ClientSettings = EventStore.shared.settings) throws{
        self.clientSettings = settings
        let channel = try GRPCChannelPool.with(settings: clientSettings)
        self.underlyingClient = .init(channel: channel)
        self.streamSelection = selection
    }
    
    
}


@available(macOS 10.15, *)
extension PersistentSubscriptions{
    
    //MARK: - Create Action
    public static func createOn(streamSelection selection: Create.StreamSelection, group: String, options: Create.Options, settings: ClientSettings = EventStore.shared.settings) async throws -> Self{
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let underlyingClient: UnderlyingClient = .init(channel: channel)
        
        let handler: Create = .init(streamSelection: selection, groupName: group, options: options)
        let request = try handler.build()
        
        try await handler.handle(response: underlyingClient.create(request))
        
        return switch selection{
        case .all:
            try .init(selection: .all, settings: settings)
        case .specified(let streamIdentifier, _):
            try .init(selection: .specified(streamIdentifier: streamIdentifier), settings: settings)
        }

    }
    
    public static func createOn(streamSelection selection: Create.StreamSelection, group: String, settings: ClientSettings = EventStore.shared.settings, configure: (_ options: Create.Options)->Create.Options) async throws -> Self{
        
        let options = configure(.init())
        return try await createOn(streamSelection: selection, group: group, options: options, settings: settings)
    }
    
    
    
    
    //MARK: - Update Action
    
    private func update(streamSelection selection: Update.StreamSelection, groupName: String, options: Update.Options) async throws {
        
        let handler = Update(streamSelection: selection, groupName: groupName, options: options)
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
        
    }
    
    private func update(streamSelection selection: Update.StreamSelection, groupName: String, configure: (_ options: Update.Options)->Update.Options) async throws {
        
        let options = configure(.init())
        try await update(streamSelection: selection, groupName: groupName, options: options)
        
    }
    
    //MARK: - Delete Actions
    
    public static func deleteOn(streamSelection selection: StreamSelection, groupName: String, settings: ClientSettings = EventStore.shared.settings) async throws {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let underlyingClient: UnderlyingClient = .init(channel: channel)
        
        let handler = Delete(streamSelection: selection, groupName: groupName)
        let request = try handler.build()
        
        try await handler.handle(response: underlyingClient.delete(request))
    }
    
    
}



@available(macOS 10.15, *)
extension PersistentSubscriptions {
    
//    public enum StreamSelection {
//        case all(position: Stream.Cursor<Stream.Read.Position>, filterOption: FilterOption? = nil)
//        case specified(streamIdentifier: Stream.Identifier, revision: Stream.Cursor<UInt64>)
//    }
    
    public enum StreamSelection {
        case all
        case specified(streamIdentifier: Stream.Identifier)
    }
    
    public enum TimeSpan{
        case ticks(Int64)
        case ms(Int32)
    }
    
}
