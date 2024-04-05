//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/31.
//

import Foundation
import EventStoreDB

public protocol Repository{
    associatedtype ReadEvents
    associatedtype AggregateRoot: Aggregate
    
    func find(id: AggregateRoot.ID) async throws -> ReadEvents?
    func get(id: AggregateRoot.ID) async throws -> AggregateRoot
    func save(entity: AggregateRoot) async throws
    func delete(id: AggregateRoot.ID) async throws
}

extension Repository {
    public mutating func delete(entity: AggregateRoot) async throws {
        try await delete(id: entity.id)
    }
}

extension Repository where ReadEvents: Sequence, ReadEvents.Element: Event{
    
    public func get(id: AggregateRoot.ID) async throws -> AggregateRoot{
        
        var aggregate = AggregateRoot.init(id: id)
        guard let events = try await find(id: id) else {
            return aggregate
        }
        
        for event in events{
            try aggregate.add(event: event)
        }
        return aggregate
    }
    
}

extension Repository where ReadEvents == AsyncStream<ReadEvent> {
    
    public func get(id: AggregateRoot.ID) async throws -> AggregateRoot{
        var aggregate = AggregateRoot.init(id: id)
        
        guard let events = try await find(id: id) else {
            return aggregate
        }
        
        for try await readEvent in events {
            if let event = try AggregateRoot.EventType.init(readEvent: readEvent) {
                try aggregate.add(event: event)
            }
            aggregate.revision = readEvent.recordedEvent.revision
        }
        return aggregate
    }
    
}



