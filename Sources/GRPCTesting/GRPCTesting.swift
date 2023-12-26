//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/9.
//

import Foundation
import EventStoreDB
import GRPC
import NIOSSL
import GRPCSupport

//enum 花色: Int{
//    case 梅花
//    case 方塊
//    case 愛心
//    case 黑桃
//}
//
//enum Rank: Int{
//    case ２ = 2
//    case ３
//    case ４
//    case ５
//    case ６
//    case ７
//    case ８
//    case ９
//    case １０
//    case J
//    case Q
//    case K
//    case A
//}
//
//struct Poker {
//    let _花色: 花色
//    let rank: Rank
//    
//    static var 🂡: Self = .init(_花色: .黑桃, rank: .A)
//    static var 🂢: Self = .init(_花色: .黑桃, rank: .２)
//    static var 🂣: Self = .init(_花色: .黑桃, rank: .３)
//}
//
//let x = Poker(_花色: .愛心, rank: .A)

//enum Poker {
//    case unit(花色, Int)
//    
//    static var A: Self{ .unit(.愛心, 0) }
//    
//}


@available(macOS 13.0, *)
@main
struct GRPCTesting {
    
    @available(macOS 13.0, *)
    public static func main() async throws{
        
        var settings: ClientSettings = "esdb://admin:changeit@localhost:2111,localhost:2112,localhost:2113?keepAliveTimeout=10000&keepAliveInterval=10000"
        
        settings.configuration.trustRoots = .file("/Users/gradyzhuo/Library/CloudStorage/Dropbox/Work/jw/mendesky/EventStore/samples/server/certs/ca/ca.crt")
        
        try EventStoreDB.using(settings: settings)
                             
                        
                             
//        var configuration = TLSConfiguration.clientDefault
//        configuration.certificateChain = [
//            .certificate(try .init(file: "/Users/gradyzhuo/Library/CloudStorage/Dropbox/Work/jw/mendesky/EventStore/samples/server/certs/ca/ca.pem", format: .pem))
//        ]
//        configuration.trustRoots = .file("/Users/gradyzhuo/Library/CloudStorage/Dropbox/Work/jw/mendesky/EventStore/samples/server/certs/ca/ca.crt")
//        configuration.certificateVerification = .noHostnameVerification
        
        
        
//        if EventStoreDB.shared.settings.tls {
//            EventStoreDB.shared.settings.transportSecurity = .tls(.makeClientConfigurationBackedByNIOSSL(configuration: configuration))
//        }
//
        
        let client1 = try UserClient()
//        let user = try await  client1.create(loginName: "gradyzhuo", password: "1234", fullName: "Grady Zhuo")
//        
        for await user in try client1.details(loginName: "gradyzhuo"){
            print("user:", user)
        }
        
        let members = try await GossipClient.read()
        
        
        let client = try PersistentSubscriptionsClient(selection: .specified(streamIdentifier: "testing"), groupName: "subscription-group")

        
        
        print("info:", try await client.getInfo())
        print("======================")
        
        let results = try await PersistentSubscriptionsClient.list { options in
            options.listAllScriptions()
        }
        print("list:", results)
        print("======================")
        
        let m = try MonitoringClient()
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
