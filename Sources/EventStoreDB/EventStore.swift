//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/14.
//

import Foundation
import GRPC
import NIOSSL

public struct EventStore {
    public static var shared = Self()

    public internal(set) var settings: ClientSettings = .localhost()

    public static func using(settings: ClientSettings) throws {
        shared.settings = settings
    }
}
