//
//  Projection.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//
import Foundation
import GRPC

@available(macOS 13.0, *)
public struct Projection {
    internal typealias UnderlyingClient = EventStore_Client_Projections_ProjectionsAsyncClient
    
    public private(set) var mode: Mode
    public private(set) var channel: GRPCChannel
    
    public static var defaultCallOptions: GRPC.CallOptions = .init()
    
    public var callOptions: GRPC.CallOptions{
        get{
            underlyingClient.defaultCallOptions
        }
        set{
            underlyingClient.defaultCallOptions = newValue
        }
    }
    
    var underlyingClient: UnderlyingClient
    

    init(mode: Mode, channel: GRPCChannel? = nil) throws{
        self.channel = try channel ??  GRPCChannelPool.with(settings: EventStore.shared.settings)
        self.underlyingClient = .init(channel: self.channel)
        self.mode = mode
    }

    public init(name: String, emitEnable: Bool, trackEmittedStreams: Bool) throws{
        let channel = try GRPCChannelPool.with(settings: EventStore.shared.settings)
        try self.init(mode: .continuous(name: name, emitEnable: emitEnable, trackEmittedStreams: trackEmittedStreams), channel: channel)
    }
}

@available(macOS 13.0, *)
extension Projection {
    
    public enum Mode {
//        case oneTime
//        case transient(name: String)
        case continuous(name: String, emitEnable: Bool, trackEmittedStreams: Bool)
        
        public var name: String? {
            return switch self {
            case let .continuous(name, _, _):
                name
            }
        }
    }
    
//    public func state<Result>(partation: String)->Result{
////        EventStore_Client_Projections_StateResp().state
//    }
    
}


@available(macOS 13.0, *)
extension Projection {
    
    //MARK: - Create Actions
    
    public static func create(mode: Mode, query: String, settings: ClientSettings = EventStore.shared.settings) async throws -> Self {
        let channel = try GRPCChannelPool.with(settings: settings)
        let client = UnderlyingClient.init(channel: channel)
        
        
        switch mode {
//        case .oneTime:
//            $0.oneTime = .init()
//        case let .transient(name):
//            $0.transient = .with{
//                $0.name = name
//            }
        case let .continuous(name, emitEnable, trackEmittedStreams):
            let options: ContinuousCreate.Options = 
                .init()
                .emit(enabled: emitEnable)
                .trackEmittedStreams(trackEmittedStreams)
            let handler = ContinuousCreate(name: name, query: query, options: options)
            let request = try handler.build()
            let _ = try await handler.handle(response: client.create(request))
            
            return try .init(mode: mode, channel: channel)
        }
        
    }
    
    public static func create(name: String, query: String, options: ContinuousCreate.Options, settings: ClientSettings = EventStore.shared.settings) async throws -> Self {
        
        let mode: Mode = .continuous(name: name, emitEnable: options.emitEnabled, trackEmittedStreams: options.trackEmittedStreams)
        return try await create(mode: mode, query: query, settings: settings)
    }
    
    public static func create(name: String, query: String, settings: ClientSettings = EventStore.shared.settings, configure: (_ options: ContinuousCreate.Options)->ContinuousCreate.Options = { $0 }) async throws -> Self {

        let options = configure(.init())
        
        let mode: Mode = .continuous(name: name, emitEnable: options.emitEnabled, trackEmittedStreams: options.trackEmittedStreams)
        return try await create(mode: mode, query: query, settings: settings)
    }
    
    
    //MARK: - Update Actions
    
    public func update(query: String? = nil, options: Update.Options) async throws {
        
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Update(name: name, query: query, options: options)
        }
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
    }
    
    public func update(query: String? = nil, configure: (_ options: Update.Options)->Update.Options = { $0 }) async throws {
        
        let options =  configure(.init())
        try await update(query: query, options: options)
    }
    
    //MARK: - Delete Actions
    public static func delete(name: String, options: Delete.Options, settings: ClientSettings = EventStore.shared.settings) async throws {
        let channel = try GRPCChannelPool.with(settings: settings)
        let client = UnderlyingClient.init(channel: channel)
        
        let handler = Delete(name: name, options: options)
        
        let request = try handler.build()
        try await handler.handle(response: client.delete(request))
    }
    
    public static func delete(name: String, settings: ClientSettings = EventStore.shared.settings, configure: (_ options: Delete.Options)->Delete.Options = { $0 }) async throws {
        
        let options = configure(.init())
        try await delete(name: name, options: options, settings: settings)
    }
    
    //MARK: - Statistics Actions
    public func statistics() async throws -> Statistics.Responses {
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Statistics(name: name, options: .init().set(mode: .continuous))
        }
        
        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.statistics(request))
    }
    
    public static func statistics(name: String, options: Statistics.Options, settings: ClientSettings = EventStore.shared.settings) async throws -> Statistics.Responses {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let client = UnderlyingClient.init(channel: channel)
        
        let handler = Statistics(name: name, options: options)
        
        let request = try handler.build()
        return try handler.handle(responses: client.statistics(request))
    }
    
    public static func statistics(name: String, settings: ClientSettings = EventStore.shared.settings, configure: (_ options: Statistics.Options)->Statistics.Options = { $0 }) async throws -> Statistics.Responses {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let client = UnderlyingClient.init(channel: channel)
        
        let handler = Statistics(name: name, options: configure(.init()))
        
        let request = try handler.build()
        return try handler.handle(responses: client.statistics(request))
    }
    
    
    //MARK: - Disable Actions
    
    public func disable(writeCheckpoint: Bool) async throws {
        
        return try await disable { options in
            options.writeCheckpoint(enabled: writeCheckpoint)
        }
    }
    
    public func disable(options: Disable.Options) async throws {
        
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Disable(name: name, options: options)
        }
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.disable(request))
    }
    
    public func disable(configure: (_ options: Disable.Options)->Disable.Options = { $0 }) async throws {
        
        let options =  configure(.init())
        try await disable(options: options)
    }
    
    
    //MARK: - Enable Actions
    
    public func enable() async throws {
        
        return try await enable{ $0 }
    }
    
    public func enable(options: Enable.Options) async throws {
        
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Enable(name: name, options: options)
        }
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.enable(request))
    }
    
    public func enable(configure: (_ options: Enable.Options)->Enable.Options = { $0 }) async throws {
        
        let options =  configure(.init())
        try await enable(options: options)
    }
    
    
}
