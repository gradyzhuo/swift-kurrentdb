// The Swift Programming Language
// https://docs.swift.org/swift-book

import GRPC
import Foundation
import NIOSSL

public struct EventStoreDB {
    public static var shared = Self.init()
    
    public internal(set) var settings: ClientSettings = .localhost()
    
    public static func using(settings: ClientSettings) throws {
        shared.settings = settings
    }
    
    @available(macOS 13.0, *)
    public static func subscribeToAll(groupName: String, bufferSize: Int32 = 1000, uuidOption: UUID.Option = .string) async throws -> AsyncStream<ReadEvent>{
        let client = try PersistentSubscriptionsClient(selection: .all, groupName: groupName)
        let options: PersistentSubscriptionsClient.Read.Options = 
            .init()
            .set(bufferSize: bufferSize)
            .set(uuidOption: uuidOption)
        
        let results = try await client.read(options: options)
        return AsyncStream.init { continuation in
            Task {
                for await result in results {
                    continuation.yield(result.event)
                }
                continuation.finish()
            }
        }

    }
    
//    @available(macOS 13.0, *)
//    public static func subscribeToAll(groupName: String) async throws{
//        let client = try PersistentSubscriptions(selection: .all, groupName: groupName)
//        Task{
//            
//        }
//    }
    
}

//@available(macOS 13.0, *)
//struct EventStoreDBClient{
//    
//    let settings: EventStoreDBSettings
//    let channel: GRPCChannel
//    
////    public var version: String {
////        
////    }
//    
//    public init(settings: EventStoreDBSettings = .standard) throws {
//        self.settings = settings
//        self.channel = try settings.makeChannel()
//    }
//    
////    public convenience init(connectionString conn: String){
////        
////    }
//    
//    public func appendStream(name: String){
////        let r = Streams.ReadRequest.readAll.build()
////        
//    }
//    
//    
//}

