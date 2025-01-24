//
//  ReadEvent.swift
//
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation
import GRPCEncapsulates

public struct ReadEvent: Sendable {
    public internal(set) var recordedEvent: RecordedEvent
    public internal(set) var linkedRecordedEvent: RecordedEvent?
    public internal(set) var commitPosition: StreamPosition?

    public var noPosition: Bool {
        commitPosition == nil
    }

    package init(event: RecordedEvent, link: RecordedEvent? = nil, commitPosition: StreamPosition? = nil) {
        recordedEvent = event
        linkedRecordedEvent = link
        self.commitPosition = commitPosition
    }

    package init(message: EventStore_Client_Streams_ReadResp.ReadEvent) throws {
        recordedEvent = try .init(message: message.event)
        linkedRecordedEvent = try message.hasLink ? .init(message: message.link) : nil

        if let position = message.position {
            switch position {
            case .noPosition:
                commitPosition = nil
            case let .commitPosition(commitPosition):
                self.commitPosition = .at(commitPosition: commitPosition)
            }
        } else {
            commitPosition = nil
        }
    }
}
