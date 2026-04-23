//
//  ReadEvent.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation
import GRPCEncapsulates

/// A single event returned from a stream read operation, pairing the recorded event with its link and position.
public struct ReadEvent: Sendable {
    /// The primary recorded event.
    public internal(set) var record: RecordedEvent

    /// The resolved link event when reading from a projection or linked stream; `nil` otherwise.
    public internal(set) var link: RecordedEvent?

    /// Global commit position of this event; `nil` when no position was provided by the server.
    public internal(set) var commitPosition: StreamPosition?

    /// `true` when the server returned no commit position for this event.
    public var noPosition: Bool {
        commitPosition == nil
    }

    package init(recorded: RecordedEvent, link: RecordedEvent? = nil, commitPosition: StreamPosition? = nil) {
        record = recorded
        self.link = link
        self.commitPosition = commitPosition
    }

    package init(message: EventStore_Client_Streams_ReadResp.ReadEvent) throws(KurrentError) {
        let recorded: RecordedEvent = try .init(message: message.event)
        let link: RecordedEvent? = try message.hasLink ? .init(message: message.link) : nil

        let commitPosition: StreamPosition? = switch message.position {
        case .noPosition:
            nil
        case let .commitPosition(commitPosition):
            .at(commitPosition: commitPosition)
        case .none:
            nil
        }

        self.init(recorded: recorded, link: link, commitPosition: commitPosition)
    }
}
