//
//  EventStore_Client_Streams_AppendResp+Additions.swift
//
//
//  Created by Ospark.org on 2023/10/19.
//

import Foundation

@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.Success.OneOf_CurrentRevisionOption {
    typealias Represented = Stream.Append.Response.CurrentRevisionOption

    func represented() -> Represented {
        switch self {
        case let .currentRevision(revision):
            return .revision(revision)
        case .noStream:
            return .noStream
        }
    }
}

@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.WrongExpectedVersion.OneOf_CurrentRevisionOption {
    typealias Represented = Stream.Append.Response.CurrentRevisionOption

    func represented() -> Represented {
        switch self {
        case let .currentRevision(revision):
            return .revision(revision)
        case .currentNoStream:
            return .noStream
        }
    }
}

@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.WrongExpectedVersion.OneOf_ExpectedRevisionOption {
    typealias Represented = Stream.Append.Response.Wrong.ExpectedRevisionOption

    func represented() -> Represented {
        switch self {
        case .expectedAny:
            return .any
        case .expectedNoStream:
            return .noStream
        case .expectedStreamExists:
            return .streamExists
        case let .expectedRevision(revision):
            return .revision(revision)
        }
    }
}

@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.Success.OneOf_PositionOption {
    typealias Represented = Stream.Position.Option

    func represented() -> Represented {
        switch self {
        case let .position(position):
            return .position(.init(commit: position.commitPosition, prepare: position.preparePosition))
        case .noPosition:
            return .noPosition
        }
    }
}
