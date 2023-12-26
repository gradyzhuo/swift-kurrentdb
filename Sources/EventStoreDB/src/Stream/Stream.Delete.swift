//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension StreamClient {
    public struct Delete: UnaryUnary {
        
        public typealias Request = GenericGRPCRequest<EventStore_Client_Streams_DeleteReq>
        
        public let streamIdentifier: StreamClient.Identifier
        public let options: Options
        
        internal init(streamIdentifier: StreamClient.Identifier, options: Options){
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


@available(macOS 13.0, *)
extension StreamClient.Delete {
    
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Streams_DeleteResp
        
        public internal(set) var position: StreamClient.Position.Option
        
        public init(from message: UnderlyingMessage) throws{
            let position = message.positionOption?.represented() ?? .noPosition
            self.position = position
        }
    }
}
