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
    
    var client: UnderlyingClient
    
//    public var name: String?{
//        get{
//            switch mode {
//            case let .continuous(name, _, _):
//                return name
//            }
//        }
//    }
    
    init(mode: Mode, channel: GRPCChannel) throws{
        self.channel = channel
        self.client = .init(channel: channel)
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
    
    public static func create(mode: Mode, query: String) async throws -> Self {
        let channel = try GRPCChannelPool.with(settings: EventStore.shared.settings)
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
            
            return try await .init(mode: mode, channel: channel).update()
        }
        
    }
    
    public static func create(name: String, query: String, options: ContinuousCreate.Options) async throws -> Self {
        let channel = try GRPCChannelPool.with(settings: EventStore.shared.settings)
        let client = UnderlyingClient.init(channel: channel)
        
        let mode: Mode = .continuous(name: name, emitEnable: options.emitEnabled, trackEmittedStreams: options.trackEmittedStreams)
        return try await create(mode: mode, query: query)
    }
    
    public static func create(name: String, query: String, configure: (_ options: ContinuousCreate.Options)->ContinuousCreate.Options = { $0 }) async throws -> Self {
        let channel = try GRPCChannelPool.with(settings: EventStore.shared.settings)
        let client = UnderlyingClient.init(channel: channel)
        
        var options = configure(.init())
        
        let mode: Mode = .continuous(name: name, emitEnable: options.emitEnabled, trackEmittedStreams: options.trackEmittedStreams)
        return try await create(mode: mode, query: query)
    }
    
    
    public func update() async throws -> Self {
        return self
    }
}
