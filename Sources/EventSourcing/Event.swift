//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/4/1.
//

import Foundation
import EventStoreDB


public protocol Event: Codable {
    var eventType: String { get }
    
    init?(readEvent: ReadEvent) throws
}

extension Event {
    
    public static func restore(from recordedEvent: RecordedEvent) throws -> Self {
        let decoder = JSONDecoder()
        return try decoder.decode(Self.self, from: recordedEvent.data)
    }
    
    public func toEventData(eventType: String = "\(Self.Type.self)") throws -> EventData{
        let encoder = JSONEncoder()
        return try .init(eventType: eventType, payload: encoder.encode(self))
    }
}
