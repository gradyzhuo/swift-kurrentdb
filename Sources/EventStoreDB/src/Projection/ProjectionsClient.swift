//
//  Projection.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//
import Foundation
import GRPC
import SwiftProtobuf
import GRPCSupport

@available(macOS 13.0, *)
public struct ProjectionsClient: EventStoreClient {
    public typealias UnderlyingClient = EventStore_Client_Projections_ProjectionsAsyncClient
    
    public private(set) var mode: Mode
    public var channel: GRPCChannel
    public var clientSettings: ClientSettings
    
    public static var defaultCallOptions: GRPC.CallOptions = .init()

    init(mode: Mode, settings: ClientSettings = EventStoreDB.shared.settings) throws{
        self.clientSettings = settings
        self.channel = try GRPCChannelPool.with(settings: clientSettings)
        self.mode = mode
    }

    public init(name: String, emitEnable: Bool, trackEmittedStreams: Bool, settings: ClientSettings = EventStoreDB.shared.settings) throws{
        try self.init(mode: .continuous(name: name, emitEnable: emitEnable, trackEmittedStreams: trackEmittedStreams), settings: settings)
    }
    
    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        return .init(channel: channel, defaultCallOptions: callOptions)
    }
}

@available(macOS 13.0, *)
extension ProjectionsClient {
    
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
     
}


@available(macOS 13.0, *)
extension ProjectionsClient {
    
    //MARK: - Create Actions
    
    public static func create(mode: Mode, query: String, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Self {
        let channel = try GRPCChannelPool.with(settings: settings)
        var client: UnderlyingClient = .init(channel: channel)
        try client.configure(by: settings)
        
        
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
            
            return try .init(mode: mode, settings: settings)
        }
        
    }
    
    public static func create(name: String, query: String, options: ContinuousCreate.Options, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Self {
        
        let mode: Mode = .continuous(name: name, emitEnable: options.emitEnabled, trackEmittedStreams: options.trackEmittedStreams)
        return try await create(mode: mode, query: query, settings: settings)
    }
    
    public static func create(name: String, query: String, settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: ContinuousCreate.Options)->ContinuousCreate.Options) async throws -> Self {

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
    
    public func update(query: String? = nil, configure: (_ options: Update.Options)->Update.Options) async throws {
        
        let options =  configure(.init())
        try await update(query: query, options: options)
    }
    
    //MARK: - Delete Actions
    public static func delete(name: String, options: Delete.Options, settings: ClientSettings = EventStoreDB.shared.settings) async throws {
        let channel = try GRPCChannelPool.with(settings: settings)
        var client = UnderlyingClient.init(channel: channel)
        try client.configure(by: settings)
        
        let handler = Delete(name: name, options: options)
        
        let request = try handler.build()
        try await handler.handle(response: client.delete(request))
    }
    
    public static func delete(name: String, settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: Delete.Options)->Delete.Options) async throws {
        
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
    
    public static func statistics(name: String, options: Statistics.Options, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Statistics.Responses {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        var client = UnderlyingClient.init(channel: channel)
        try client.configure(by: settings)
        
        let handler = Statistics(name: name, options: options)
        
        let request = try handler.build()
        return try handler.handle(responses: client.statistics(request))
    }
    
    public static func statistics(name: String, settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: Statistics.Options)->Statistics.Options) async throws -> Statistics.Responses {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        let client = UnderlyingClient.init(channel: channel)
        
        let handler = Statistics(name: name, options: configure(.init()))
        
        let request = try handler.build()
        return try handler.handle(responses: client.statistics(request))
    }
    
    //MARK: - Enable Actions
    
    public func enable() async throws {
        
        let options = Enable.Options.init()
        try await enable(options: options)
    }
    
    internal func enable(options: Enable.Options) async throws {
        
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Enable(name: name, options: options)
        }
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.enable(request))
    }
    
    //MARK: - Disable & Abort Actions
    
    public func disable() async throws {
        let options = Disable.Options().writeCheckpoint(enabled: true)
        return try await disable(options: options)
    }
    
    public func abort() async throws {
        let options = Disable.Options().writeCheckpoint(enabled: false)
        return try await disable(options: options)
    }
    
    internal func disable(options: Disable.Options) async throws {
        
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Disable(name: name, options: options)
        }
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.disable(request))
    }
    
    //MARK: - Reset Actions
    
    public func reset() async throws {
        
        let options: Reset.Options = .init().writeCheckpoint(enable: false)
        try await reset(options: options)
    }
    
    internal func reset(options: Reset.Options) async throws {
        
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Reset(name: name, options: options)
        }
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.reset(request))
    }
    
    
    
    //MARK: - State Actions
    
    public func getState<Value: Decodable>(casting: Value.Type, options: State.Options) async throws -> Value{
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            State(name: name, options: options)
        }
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.state(request))
        return try response.decode(to: Value.self)
    }
    
    public func getState<Value: Decodable>(casting: Value.Type, configure: (_ options: State.Options) -> State.Options) async throws -> Value{
        let options = configure(.init())
        return try await getState(casting: casting, options: options)
    }
    
    public func getState<Value: Decodable>(configure: (_ options: State.Options) -> State.Options) async throws -> Value{
        let options = configure(.init())
        return try await getState(casting: Value.self, options: options)
    }
    
    //MARK: - Result Actions
    
    public func getResult<Value: Decodable>(casting: Value.Type, options: Result.Options) async throws ->Value{
        let handler = switch self.mode {
        case let .continuous(name, _, _):
            Result(name: name, options: options)
        }
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.result(request))
        
        return try response.decode(to: Value.self)
    }
    
    public func getResult<Value: Decodable>(casting: Value.Type, configure: (_ options: Result.Options) -> Result.Options) async throws ->Value{
        let options = configure(.init())
        return try await getResult(casting: casting, options: options)
    }
    
    public func getResult<Value: Decodable>(configure: (_ options: Result.Options) -> Result.Options) async throws ->Value{
        let options = configure(.init())
        return try await getResult(casting: Value.self, options: options)
    }
    
    //MARK: - RestartSubsystem Actions
    
    public static func restartSubsystem(settings: ClientSettings = EventStoreDB.shared.settings) async throws{
        
        let channel = try GRPCChannelPool.with(settings: settings)
        var client = UnderlyingClient(channel: channel)
        try client.configure(by: settings)
        
        let handler = RestartSubsystem()
        try await handler.handle(response: client.restartSubsystem(handler.build()))
        
    }
}
