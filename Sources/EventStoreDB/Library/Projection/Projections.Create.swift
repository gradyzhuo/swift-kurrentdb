//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/11/22.
//

import Foundation
import SwiftProtobuf

@available(macOS 13.0, *)
extension Projection {
    public struct ContinuousCreate:  UnaryUnary {
        
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_CreateResp>
        
        public let name: String
        public let query: String
        public let options: Options
        
        init(name: String, query: String, options: Options) {
            self.name = name
            self.query = query
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.build()
                $0.options.continuous.name = name
                $0.options.query = query
            }
        }
    }
}

@available(macOS 13.0, *)
extension Projection.ContinuousCreate {
    
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_Projections_CreateReq
        
        
    }
    
}


//MARK: - The Options of Continuous Create.
@available(macOS 13.0, *)
extension Projection.ContinuousCreate {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_CreateReq.Options
        
        var options: UnderlyingMessage
        
        public var emitEnabled: Bool {
            didSet{
                options.continuous.emitEnabled = emitEnabled
            }
        }
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        public var trackEmittedStreams: Bool{
            didSet{
                options.continuous.trackEmittedStreams = trackEmittedStreams
            }
        }
        
        public init() {
            self.options = .with{
                $0.continuous = .init()
            }
            self.emitEnabled = true
            self.trackEmittedStreams = true
        }
        
        @discardableResult
        public func emit(enabled: Bool)->Self{
            self.emitEnabled = enabled
            return self
        }
        
        @discardableResult
        public func trackEmittedStreams(_ trackEmittedStreams: Bool)->Self{
            self.trackEmittedStreams = trackEmittedStreams
            return self
        }
        
    }
}
