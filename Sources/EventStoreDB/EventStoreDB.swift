// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import GRPC
import NIOSSL

public struct EventStoreDB {
    public static var shared = Self()

    public internal(set) var settings: ClientSettings = .localhost()

    public static func using(settings: ClientSettings) throws {
        shared.settings = settings
    }
    
    
    public static func streamClient() throws -> StreamClient{
        let channel = try GRPCChannelPool.with(settings: shared.settings)
        let callOptions = try shared.settings.makeCallOptions()
        return .init(channel: channel, callOptions: callOptions)
    }
    
    
}




