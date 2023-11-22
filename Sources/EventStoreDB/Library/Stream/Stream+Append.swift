//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/31.
//

import Foundation

@available(macOS 10.15, *)
extension Stream {
    
    public func append(event: EventData, options: Append.Options = .init()) async throws -> Append.Client.BingingResponse {
        
        let client = Stream.Append.Client.init(underlyingClient: self.underlyingClient)
        
        let requests = try Append.Client.buildRequests(streamIdentifier: identifier, event: event, options: options)
        
        return try await client.call(requests: requests)
    }
    
    public func append(event: EventData, configure: (_ options: Append.Options)->Append.Options = { $0 }) async throws -> Append.Client.BingingResponse {
       
        let options = configure(.init())
        return try await self.append(event: event, options: options)
        
    }
}
