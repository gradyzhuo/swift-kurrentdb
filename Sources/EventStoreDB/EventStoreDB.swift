// The Swift Programming Language
// https://docs.swift.org/swift-book

import GRPC
import Foundation
//import ServiceContextModule

// ServiceContext.topLevel

//@available(macOS 13.0, *)
public struct EventStore {
    public static var shared = Self.init()
    
    public private(set) var settings: ClientSettings = .localhost()

    internal private(set) lazy var channel: GRPCChannel = {
        try! GRPCChannelPool.with(settings: settings)
    }()
    
    public static func using(settings: ClientSettings) throws {
        shared.settings = settings
        shared.channel = try GRPCChannelPool.with(settings: settings)
    }
    
    
    public func subscribe(){
        
    }
    
}

//@available(macOS 10.15, *)
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

