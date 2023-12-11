//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/11/2.
//

import Foundation
import GRPCSupport

@available(macOS 10.15, *)
extension Stream {
    public struct Tombstone: UnaryUnary{
        public typealias Request = GenericGRPCRequest<EventStore_Client_Streams_TombstoneReq>
        
        public let streamIdentifier: Stream.Identifier
        public let options: Options
        
        init(streamIdentifier: Stream.Identifier, options: Options) {
            self.options = options
            self.streamIdentifier = streamIdentifier
        }
        
        public func build() throws -> EventStore_Client_Streams_TombstoneReq {
            try .with{
                var options = options.build()
                options.streamIdentifier = try streamIdentifier.build()
                $0.options = options
            }
        }
        
    }
}

@available(macOS 10.15, *)
extension Stream.Tombstone {
    
    public struct Response: GRPCResponse {
        
        public typealias PositionOption = Stream.Position.Option
        
        public typealias UnderlyingMessage = EventStore_Client_Streams_TombstoneResp
        
        public internal(set) var position: PositionOption
        
        public init(from message: UnderlyingMessage) throws {
            let position = message.positionOption?.represented() ?? .noPosition
            self.position = position
        }
    }
}

