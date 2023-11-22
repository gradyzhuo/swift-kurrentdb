//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/19.
//

import Foundation

@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.Success.OneOf_CurrentRevisionOption {
    internal typealias Represented = Stream.Append.Response.CurrentRevisionOption
    
    internal func represented() -> Represented {
        switch self {
        case .currentRevision(let revision):
            return .revision(revision)
        case .noStream(_):
            return .noStream
        }
    }
    
}

@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.WrongExpectedVersion.OneOf_CurrentRevisionOption{
    
    internal typealias Represented = Stream.Append.Response.CurrentRevisionOption
    
    internal func represented() -> Represented {
        switch self {
        case .currentRevision(let revision):
            return .revision(revision)
        case .currentNoStream(_):
            return .noStream
        }
    }
    
}

@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.WrongExpectedVersion.OneOf_ExpectedRevisionOption{
    
    internal typealias Represented = Stream.Append.Response.Wrong.ExpectedRevisionOption
    
    internal func represented() -> Represented {
        switch self {
        case .expectedAny(_):
            return .any
        case .expectedNoStream(_):
            return .noStream
        case .expectedStreamExists(_):
            return .streamExists
        case .expectedRevision(let revision):
            return .revision(revision)
        }
    }
    
}



@available(macOS 10.15, *)
extension EventStore_Client_Streams_AppendResp.Success.OneOf_PositionOption {
    
    internal typealias Represented = Stream.Position.Option
    
    internal func represented() -> Represented {
        switch self {
        case .position(let position):
            return .position(.init(commit: position.commitPosition, prepare: position.preparePosition))
        case .noPosition(_):
            return .noPosition
        }
    }
    
}


