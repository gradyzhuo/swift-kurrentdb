//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation
import GRPC

protocol GRPClientBuilder {
    var channel: GRPCChannel { get }
}


// @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
// final public class GossipClient: GRPClientBuilder{
//     public internal(set) var channel: GRPC.GRPCChannel
    
//     public init(channel: GRPCChannel? = nil) {
//         self.channel = try! channel ?? ClientSettings.localhost.makeChannel()
//     }
    
//     public func read() async throws -> EventStore_Client_Gossip_ClusterInfo{
//         let client = EventStore_Client_Gossip_GossipAsyncClient(channel: channel)
        
//         let request = EventStore_Client_Empty()
//         return try await client.read(request)
//     }
// }



