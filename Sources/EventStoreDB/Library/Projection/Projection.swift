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
    
    public var name: String?{
        get{
            switch mode {
            case let .continuous(name, _, _):
                return name
            }
        }
    }
    
    public enum Mode {
//        case oneTime
//        case transient(name: String)
        case continuous(name: String, emitEnable: Bool, trackEmittedStreams: Bool)
    }
    
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
    
    public func state<Result>(partation: String)->Result{
//        EventStore_Client_Projections_StateResp().state
    }
    
}


@available(macOS 13.0, *)
extension Projection {
    
    public static func create(query: String, mode: Mode) async throws -> Self {
        let channel = try GRPCChannelPool.with(settings: EventStore.shared.settings)
        let client = UnderlyingClient.init(channel: channel)
        
        let request = EventStore_Client_Projections_CreateReq.with{
            $0.options = .with{
                $0.query = query
                switch mode {
//                case .oneTime:
//                    $0.oneTime = .init()
//                case let .transient(name):
//                    $0.transient = .with{
//                        $0.name = name
//                    }
                case let .continuous(name, emitEnable, trackEmittedStreams):
                    $0.continuous = .with{
                        $0.name = name
                        $0.emitEnabled = emitEnable
                        $0.trackEmittedStreams = trackEmittedStreams
                    }
                }
            }
        }
        
        let _ = try await client.create(request)
        return try .init(mode: mode, channel: channel)
    }
}
