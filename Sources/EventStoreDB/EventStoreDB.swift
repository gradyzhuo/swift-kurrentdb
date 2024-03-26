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
    
}




