//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation
import GRPC
import NIO

protocol GRPClientBuilder {
    var channel: GRPCChannel { get }
}


@available(macOS 13.0, *)
func test() async throws {
    
    try EventStore.using(settings: .localhost())
    
//    let stream = try Stream(identifier: "account_stream")
//    let response = try await stream.append(id: .init(), type: "AccountUpdated", content: ["x":"y"])
    
//    let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
//    let channel = try GRPCChannelPool.with(target: .hostAndPort("localhost", 2113), transportSecurity: .plaintext, eventLoopGroup: group)
//    let client = EventStore_Client_Streams_StreamsAsyncClient(channel: channel)
//    
//    var request = EventStore_Client_Streams_AppendReq()
//    request.options.any = .init()
//    request.options.streamIdentifier = .init()
//    request.options.streamIdentifier.streamName = "".data(using: .utf8)!
//    
//
//    let request = EventStore_Client_Streams_AppendReq.with{
//        $0.options.any = .init()
//        $0.options.streamIdentifier = .init()
//        $0.options.streamIdentifier.streamName = "".data(using: .utf8)!
//    }
//    
//    
//    EventStore_Client_Streams_AppendReq.with{
//        $0.options.any = EventStore_Client_Empty.init()
//    }
//    
//    client.append([
//        EventStore_Client_Streams_AppendReq.with{
//            $0.options.any = EventStore_Client_Empty.init()
//        },
//        EventStore_Client_Streams_AppendReq.init()
//    ])
    
    
    
//    client.append([
//        .with{
//            $0.options.streamIdentifier = .with{
//                ...
//            }
//        }
//    ])
    
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



