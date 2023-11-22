//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/11/2.
//

import Foundation

@available(macOS 10.15, *)
extension Stream.Tombstone {
    
    public struct Client: UnaryUnaryCall, _GRPCClient {
        typealias UnderlyingClient = EventStore_Client_Streams_StreamsAsyncClient
        
        public typealias UnderlyingRequest = EventStore_Client_Streams_TombstoneReq
        public typealias BingingResponse = Response
        
        internal var underlyingClient: EventStore_Client_Streams_StreamsAsyncClient
        
        init(underlyingClient: UnderlyingClient) {
            self.underlyingClient = underlyingClient
        }
        
        public func call(request: UnderlyingRequest) async throws -> BingingResponse {
            
            let response = try await underlyingClient.tombstone(request)
            return .init(from: response)
            
        }
        
    }
    
}

@available(macOS 10.15, *)
extension Stream.Tombstone.Client {
    internal static func buildRequests(streamIdentifier: Stream.Identifier, options: Stream.Tombstone.Options) throws -> UnderlyingRequest {
        return try .with{
            var options = options.options
            options.streamIdentifier = try streamIdentifier.build()
            $0.options = options
        }
    }
}

@available(macOS 10.15, *)
extension Stream.Tombstone {
    
    public struct Response: UnaryResponse {
        
        public typealias PositionOption = Stream.Position.Option
        
        public typealias UnderlyingMessage = EventStore_Client_Streams_TombstoneResp
        
        public internal(set) var position: PositionOption
        
        init(from message: UnderlyingMessage) {
            let position = message.positionOption?.represented() ?? .noPosition
            self.position = position
        }
    }
}
