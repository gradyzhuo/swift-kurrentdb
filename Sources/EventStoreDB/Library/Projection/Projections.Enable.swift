//
//  File.swift
//
//
//  Created by Ospark.org on 2023/11/27.
//

import Foundation

@available(macOS 13.0, *)
extension Projections {
    
    public struct Enable: UnaryUnary {
        
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_EnableResp>
        
        public let name: String
        public let options: Options
        
        init(name: String, options: Options) {
            self.name = name
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.build()
                $0.options.name = name
            }
        }
        
    }
    
}

@available(macOS 13.0, *)
extension Projections.Enable {
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_Projections_EnableReq
    }
    
}

@available(macOS 13.0, *)
extension Projections.Enable{
    public final class Options: EventStoreOptions {
        
        public typealias UnderlyingMessage = EventStore_Client_Projections_EnableReq.Options
        
        var options: UnderlyingMessage
        
        public init() {
            self.options = .init()
        }
        
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
    }
}
