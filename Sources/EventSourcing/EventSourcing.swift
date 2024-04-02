//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/31.
//

import Foundation
import EventStoreDB

public protocol EventStoreRepository : Repository{
    var client: EventStoreDB.Client { get }
}

extension EventStoreRepository {
    internal func handle(response: StreamClient.Read.Response)->ReadEvent?{
        return switch response.content {
        case .event(readEvent: let event):
            event
        default:
            nil
        }
    }
    
    public func find(id: AggregateRoot.ID) throws -> AsyncStream<ReadEvent>{
        
        let responses = try client.read(streamName: AggregateRoot.getStreamName(id: id), cursor: .start) { options in
            options
        }
        
        return .init { continuation in
            Task {
                for await response in responses {
                    switch response.content {
                    case .event(readEvent: let event):
                        continuation.yield(event)
                    default:
                        continue
                    }
                }
                continuation.finish()
            }
        }
        
    }
    
    public func get(id: AggregateRoot.ID) async throws -> AggregateRoot {
        var aggregate = AggregateRoot.init(id: id)
        for try await readEvent in try find(id: id){
            if let event = try AggregateRoot.EventMapper.init(rawValue: readEvent.recordedEvent.eventType)?.convert(readEvent: readEvent) {
                try aggregate.add(event: event)
            }
            aggregate.revision = readEvent.recordedEvent.revision
        }
        return aggregate
    }
    
    public func save(entity: AggregateRoot) async throws{
        let events: [EventData] = try entity.events.map{
            return try .init(eventType: "\(type(of: $0))", payload: $0)
        }
        _ = try await client.appendTo(streamName: entity.streamName, events: events) { options in
            guard let revision = entity.revision else {
                return options.expectedRevision(.any)
            }
            return options.expectedRevision(.revision(revision))
        }
    }
    public func delete(id: AggregateRoot.ID) async throws{
        
    }
}
