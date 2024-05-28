//
//  EventStore.swift
//
//
//  Created by 卓俊諺 on 2024/5/14.
//

import Foundation
import GRPC
import NIOSSL

@MainActor
public struct EventStore {
    public static var shared: Self = .init()

    public internal(set) var settings: ClientSettings

    public static func using(settings: ClientSettings) throws {
        shared.settings = settings
    }
    
    init(settings: ClientSettings = .localhost()) {
        self.settings = settings
    }
}
