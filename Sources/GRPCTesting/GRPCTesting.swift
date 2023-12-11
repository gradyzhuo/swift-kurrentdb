//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/9.
//

import Foundation
import EventStoreDB
import GRPC

@available(macOS 10.15, *)
@main
struct GRPCTesting {
    
    public static func main() async throws{
        try EventStore.using(settings: .localhost())
        
        let client = try PersistentSubscriptions(selection: .specified(streamIdentifier: "testing"), groupName: "subscription-group")
        
        print("info:", try await client.getInfo())
        print("======================")
        
        let results = try await PersistentSubscriptions.list { options in
            options.listAllScriptions()
        }
        print("list:", results)
        print("======================")
        
        let m = try Monitoring()
        let x = try await m.stats(useMetadata: true, refreshTimePeriodInMs: 60000)
        Task{
            for try await y in x {
                print("monitor:", y)
            }
        }
        
        let responses = try await client.read(options: .init())
        
        for try await result in responses {
            print("ooooooooooooooooooooooooo")
            print("response:", result.event)
        }

        
        
//            do{
////                try await response.ack()
//                try await client.ack(eventIds: [response.event.event.id], subscriptionId: response.subscriptionId)
//            }catch{
//                print("error:", error)
//            }
            
//        for await response in responses {
//            print("response:", response.event)
//            
//            do{
////                try await response.ack()
//                try await client.ack(subscriptionId: response.subscriptionId, readEventIds: [response.event.event.id])
//            }catch{
//                print("error:", error)
//            }
//            
//        }
//        let channel = try GRPCChannelPool.with(settings: .localhost())
//        
//        let client = EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient(channel: channel)
//        
//        let request = EventStore_Client_PersistentSubscriptions_ReadReq.with{
//            $0.options = .with{
//                $0.streamIdentifier = .with{
//                    $0.streamName = "testing".data(using: .utf8)!
//                }
//                $0.groupName = "subscription-group"
//                $0.bufferSize = 500
//                $0.uuidOption = .with{
//                    $0.string = .init()
//                }
//            }
//        }
//        let responses = client.read([request])
//        for try await response in responses{
//            print("response:", response)
//            
//            let ackRequest = EventStore_Client_PersistentSubscriptions_ReadReq.with{
//                $0.ack = .with{
//                    $0.ids = [ .with{
//                        $0.string = response.event.event.id.string
//                    }]
//                }
//            }
//            let r = client.read([ackRequest])
//            print("r:", r)
//        }
    }
}
