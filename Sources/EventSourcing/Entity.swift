//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/31.
//

import Foundation
import EventStoreDB

public protocol Entity: Identifiable {
    static func getStreamName(id: ID) -> String
    
    var events: [Event] { get }
    
    mutating func add(event: Event) throws
    
    init(id: ID)
}

