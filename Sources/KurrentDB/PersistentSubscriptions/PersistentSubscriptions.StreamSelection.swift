//
//  PersistentSubscriptions.StreamSelection.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/31.
//

extension PersistentSubscriptions {
    public enum StreamSelection: Sendable {
        case specified(identifier: StreamIdentifier, cursor: RevisionCursor)
        case all(cursor: PositionCursor)
    }
}
