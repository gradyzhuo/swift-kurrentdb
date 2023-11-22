//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation
import GRPC

@available(macOS 10.15, *)
extension Stream {
    
    @available(macOS 13.0, *)
    public static func readAll(cursor: Read.Cursor<Read.Position>, options: Stream.Read.Options = .init(), channel: GRPCChannel? = nil) throws -> Read.Client.Responses{
        
        let channel = try channel ?? GRPCChannelPool.with(settings: EventStore.shared.settings)
        
        let underlyingClient = UnderlyingClient.init(channel: channel)
        
        let client = Self.Read.Client.init(underlyingClient: underlyingClient)
        
        let request = try Read.Client.buildRequest(cursor: cursor, options: options)

        return try client.call(request: request)
        
    }
    
    public func read(cursor: Read.Cursor<Read.Revision>, options: Stream.Read.Options = .init()) throws -> Read.Client.Responses{
        
        let client = Stream.Read.Client.init(underlyingClient: self.underlyingClient)
        
        let request = try Read.Client.buildRequest(streamIdentifier: identifier, cursor: cursor, options: options)
        
        return try client.call(request: request)
    }
    
    public func read(cursor: Read.Cursor<Read.Revision>, configure: (_ options: Stream.Read.Options) -> Stream.Read.Options = { $0 } ) throws -> Read.Client.Responses{
        
        let options = configure(.init())
        return try self.read(cursor: cursor, options: options)
        
    }
    
    
}
