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
    public internal(set) var commitPosition: Stream.Position?

    public var noPosition: Bool {
        commitPosition == nil
    }

    init(event: RecordedEvent, link: RecordedEvent? = nil, commitPosition: Stream.Position? = nil) {
        recordedEvent = event
        linkedRecordedEvent = link
        self.commitPosition = commitPosition
    }

    init(message: EventStore_Client_Streams_ReadResp.ReadEvent) throws {
        recordedEvent = try .init(message: message.event)
        linkedRecordedEvent = try message.hasLink ? .init(message: message.link) : nil

        if let position = message.position {
            switch position {
            case .noPosition:
                commitPosition = nil
            case let .commitPosition(commitPosition):
                self.commitPosition = .init(commit: commitPosition)
            }
        } else {
            commitPosition = nil
        }
    }
}
