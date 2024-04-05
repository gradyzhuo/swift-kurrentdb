//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/31.
//

import Foundation
import EventStoreDB

public protocol EventStoreRepository : Repository where ReadEvents == AsyncStream<ReadEvent>{
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
    
    public func find(id: AggregateRoot.ID) async throws -> AsyncStream<ReadEvent>?{
        
        let responses = try client.read(streamName: AggregateRoot.getStreamName(id: id), cursor: .start) { options in
            options
        }
        
        var iterator = responses.makeAsyncIterator()
        guard let response = await iterator.next() else {
            return nil
        }
        
        let firstReadEvent: ReadEvent
        switch response.content {
        case .streamNotFound(let streamName):
            throw ClientError.streamNotFound(message: "Stream \(streamName) not Found.")
        case .event(let readEvent):
            firstReadEvent = readEvent
        default:
            return nil
        }
        
        return .init { continuation in
            continuation.yield(firstReadEvent)
            
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
        try await client.delete(streamName: AggregateRoot.getStreamName(id: id)) { options in
            options.expected(revision: .streamExists)
        }
    }
}
