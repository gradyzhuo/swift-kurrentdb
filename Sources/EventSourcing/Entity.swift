//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/31.
//

import Foundation
import EventStoreDB

public protocol Entity: Identifiable, Sendable {
    var events: [any Event] { set get }
    var revision: UInt64? { set get }
    
    init(id: ID)
    
    mutating func apply<E: Event>(event: E) throws
}

extension Entity {
    public mutating func add<E: Event>(event: E) throws {
        try apply(event: event)
        self.events.append(event)
    }
}

public protocol Aggregate: Entity {
    associatedtype EventMapper:  EventMappable
    
    static var category: String { get }
}


extension Aggregate {
    public static func getStreamName(id: ID) -> String{
        return "\(Self.category)-\(id)"
    }
    
    public var streamName: String {
        return Self.getStreamName(id: id)
    }
}
