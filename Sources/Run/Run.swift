//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/18.
//

import Foundation
import EventStoreDB
import GRPC
import NIO

// struct P {
//     func test() -> String{
//         print("xxx")
//         return "k"
//     }

//     func test() async -> Int{
//         print("??")
//         return 1
//     }
// }

@main
@available(macOS 13.0, iOS 13.0, *)
public struct Run {
    
    public static func main() async throws {        
        try EventStore.using(settings: .localhost())
        
//        let channel = try settings.makeChannel()
        
//        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//        let group = PlatformSupport.makeEventLoopGroup(loopCount: 1)
//        let channel = try GRPCChannelPool.with(
//            target: .hostAndPort("localhost", 2113),
//            transportSecurity: .plaintext,
//            eventLoopGroup: group
//        )
        
        
        let o = Stream.Read.Options()
//        o.set(uuidOption: .string)
//        o.noFilter()
        
//        let rs = try Stream.readAll(cursor: .end, options: o)
////        for try await result in rs {
////            print("r:", result)
////        }
//        print("============")
        
        
        let stream = try Stream(identifier: "hello++hello")
         
        do{
            let options = Stream.Append.Options()
                .expected(revision: .streamExists)
            let appendResponse = try await stream.append(event: .init(type: "test", content: .codable(["other": "test"])), options: options)
            print("???:", appendResponse)
        }catch {
            print("error:", error)
        }
        
        
        
//        let responses = try await stream.read(cursor: .start)
//            .set(count: 10)
//            .noFilter()
//            .set(resolveLinks: false)
//            .perform()
        

//        let response = try await stream.append(event: .init(type: "test", content: .codable(["other":"test"])))
//            .expected(revision: .any)
//            .perform()
        
        
//        let responses = try await Stream.all(channel: channel).read(cursor: .start)
////            .filterOnStream(regex: ".*")
//            .noFilter()
//            .set(uuidOption: .string)
////            .countBySubscription()
//            .countBy(limit: 100)
//            .perform()
        
        let readOptions = Stream.Read.Options()
            .set(uuidOption: .string)
            .countBy(limit: 100)
        let responses = try stream.read(cursor: .start, options: readOptions)
        
//        let responses = try await Stream.init(identifier: "hello-world").read(cursor: .start)
////            .filterOnStream(regex: ".*")
//            .noFilter()
//            .set(uuidOption: .string)
////            .countBySubscription()
//            .countBy(limit: 100)
//            .perform()
        
        for try await result in responses {
            print(result)
        }
        
        
        
        
//        let deleteResponse = try await Stream.delete(identifier: "hello-world2", expected: .revision(0))
//        print("deleteResponse:", deleteResponse)
        
        
//        let deleteResponse = try await Stream.tombstone(identifier: "hello-world", expected: .revision(60))
//        print("deleteResponse:", deleteResponse)
        
//        let deleteResponse = try await stream.delete(options: .init().expected(revision: .any))
//        print("deleteResponse:", deleteResponse)
        
//        let options = Stream.ReadOptions()//.specified(name: "hello-world")
         
//        let client = EventStore_Client_Streams_StreamsAsyncClient(channel: channel)
        
//        let event:Event = .init(type: "test", content: ["test":"test"])
//        let response = try await stream.append(event: event)
//        
//        print("xxx:", response)
//        var options = Stream.ReadRequest()
//        options = options.forwards().backwards()
//        options = options.backwards()
//
//        let response = client.read(options.build())
//        for try await result in response {
//            print(result)
//        }
        
//
        
        
//        if #available(macOS 10.15, *) {
//            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
//            let group2 = PlatformSupport.makeEventLoopGroup(loopCount: 1)
//            
//            
//            
//            
//            
//            let builder = ClientConnection.usingPlatformAppropriateTLS(for: group)
//            let channel2 = builder.connect(host: "172.16.100.55", port: 2113)
//            
//
//            let x = ClientConnection.insecure(group: group)
//            let channel3 = x.connect(host: "localhost", port: 2113)
//            
//            
//            let client = EventStore_Client_Streams_StreamsAsyncClient(channel: channel)//EventStore_Client_Users_UsersAsyncClient(channel:
//            do{
//                let encoder = JSONEncoder()
//                let request1 = EventStore_Client_Streams_AppendReq.with{
//                    $0.options = .with {
//                        $0.streamIdentifier = .with{
//                            $0.streamName = "my_stream".data(using: .utf8)!
//                        }
//                        $0.expectedStreamRevision = .any(.init())
//                    }
//                }
//                
//                let request2 = try EventStore_Client_Streams_AppendReq.with {
//                    $0.proposedMessage = try .with{
//                        $0.id = .with{
//                            $0.value = .string(UUID().uuidString)
//                        }
//                        $0.data = try encoder.encode("hello ~~~~~")
//                        $0.metadata = [
//                            "type": "hello",
//                            "content-type": "application/json"
//                        ]
//                    }
//                }
//                
//                let response = try await client.append([request1, request2])
//                print("xxx:", response)
////                let append = client.makeAppendCall()
//                
//                
////                try await append.requestStream.send(request1)
////                let result1 = try await append.response.result
////                print("result1:", result1)
////                
////                
////                try await append.requestStream.send(request2)
////                let result2 = try await append.response.result
////                print("result2:", result2)
//            } catch {
//                print("error:", error)
//            }
//            
//
//            print("here")
//        } else {
//            // Fallback on earlier versions
//        }
        
        
        
        
    }
}
