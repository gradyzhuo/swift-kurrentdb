//
//  ReadEvent.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation
import GRPCEncapsulates

public struct ReadEvent: Sendable {
    
    @available(*, deprecated, renamed: "link")
    public var linkedRecordedEvent: RecordedEvent?{
        get{
            link
        }
    }
    
    @available(*, deprecated, renamed: "event")
    public var recordedEvent: RecordedEvent{
        get{
            event
        }
    }
    
    public internal(set) var event: RecordedEvent
    public internal(set) var link: RecordedEvent?
    public internal(set) var commitPosition: StreamPosition?

    public var noPosition: Bool {
        commitPosition == nil
    }

    package init(event: RecordedEvent, link: RecordedEvent? = nil, commitPosition: StreamPosition? = nil) {
        self.event = event
        self.link = link
        self.commitPosition = commitPosition
    }

    package init(message: EventStore_Client_Streams_ReadResp.ReadEvent) throws {
        let event: RecordedEvent = try .init(message: message.event)
        let link: RecordedEvent? = try message.hasLink ? .init(message: message.link) : nil
        
        let commitPosition: StreamPosition? = switch message.position {
        case .noPosition:
            nil
        case let .commitPosition(commitPosition):
            .at(commitPosition: commitPosition)
        case .none:
            nil
        }
        
        self.init(event: event, link: link, commitPosition: commitPosition)
    }
}
