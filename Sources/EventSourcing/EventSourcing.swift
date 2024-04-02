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
    
    func convert(readEvent: ReadEvent) -> Event?
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
    
    public func find(id: AggregateRoot.ID) async throws -> AggregateRoot?{
        
        let responses = try client.read(streamName: AggregateRoot.getStreamName(id: id), cursor: .start) { options in
            options
        }
        
        var iterator = responses.makeAsyncIterator()
        guard let firstResponse = await iterator.next() else {
            return nil
        }
        
        guard let readEvent = handle(response: firstResponse) else {
            return nil
        }
        
        var aggregate = AggregateRoot.init(id: id)
        
        if let event = AggregateRoot.EventMapper.init(readEvent: readEvent)?.convert() {
            try aggregate.add(event: event)
        }
        
        for try await response in responses{
            if let readEvent = handle(response: response),  let event = convert(readEvent: readEvent) {
                try aggregate.add(event: event)
            }
        }
        
        return aggregate
    }
    public func save(entity: AggregateRoot) async throws{
        let events: [EventData] = try entity.events.map{
            return try .init(eventType: "\(type(of: $0))", payload: $0)
        }
        _ = try await client.appendTo(streamName: "product::\(entity.id)", events: events) { options in
            options.expectedRevision(.any)
        }
    }
    public func delete(id: AggregateRoot.ID) async throws{
        
    }
}
