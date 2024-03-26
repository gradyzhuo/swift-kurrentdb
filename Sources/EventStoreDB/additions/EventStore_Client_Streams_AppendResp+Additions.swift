//
//  EventStore_Client_Streams_AppendResp+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/10/19.
//

import Foundation
import GRPCSupport

extension EventStore_Client_Streams_AppendResp.Success.OneOf_CurrentRevisionOption {
    typealias Represented = StreamClient.Append.Response.CurrentRevisionOption

    func represented() -> Represented {
        switch self {
        case let .currentRevision(revision):
            .revision(revision)
        case .noStream:
            .noStream
        }
    }
}

extension EventStore_Client_Streams_AppendResp.WrongExpectedVersion.OneOf_CurrentRevisionOption {
    typealias Represented = StreamClient.Append.Response.CurrentRevisionOption

    func represented() -> Represented {
        switch self {
        case let .currentRevision(revision):
            .revision(revision)
        case .currentNoStream:
            .noStream
        }
    }
}

extension EventStore_Client_Streams_AppendResp.WrongExpectedVersion.OneOf_ExpectedRevisionOption {
    typealias Represented = StreamClient.Append.Response.Wrong.ExpectedRevisionOption

    func represented() -> Represented {
        switch self {
        case .expectedAny:
            .any
        case .expectedNoStream:
            .noStream
        case .expectedStreamExists:
            .streamExists
        case let .expectedRevision(revision):
            .revision(revision)
        }
    }
}

extension EventStore_Client_Streams_AppendResp.Success.OneOf_PositionOption {
    typealias Represented = Stream.Position.Option

    func represented() -> Represented {
        switch self {
        case let .position(position):
            .position(.init(commit: position.commitPosition, prepare: position.preparePosition))
        case .noPosition:
            .noPosition
        }
    }
}
