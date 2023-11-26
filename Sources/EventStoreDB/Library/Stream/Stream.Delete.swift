//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation

@available(macOS 10.15, *)
extension Stream {
    public struct Delete: UnaryUnary {
        
        public let streamIdentifier: Stream.Identifier
        public let options: Options
        
        internal init(streamIdentifier: Stream.Identifier, options: Options){
            self.options = options
            self.streamIdentifier = streamIdentifier
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return try .with{
                $0.options = options.build()
                $0.options.streamIdentifier = try self.streamIdentifier.build()
                
            }
        }
        
    }
}


@available(macOS 10.15, *)
extension Stream.Delete {
    
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_Streams_DeleteReq
        
    }
    
    public struct Response: GRPCResponse {
        
        public typealias PositionOption = Stream.Position.Option
        
        public typealias UnderlyingMessage = EventStore_Client_Streams_DeleteResp
        
        public internal(set) var position: PositionOption
        
        public init(from message: UnderlyingMessage) throws{
            let position = message.positionOption?.represented() ?? .noPosition
            self.position = position
        }
    }
}
