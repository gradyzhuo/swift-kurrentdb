//
//  PersistentSubscriptions.StreamSelection.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/31.
//

extension PersistentSubscriptions {
    /// Defines which stream a persistent subscription reads from and where it starts.
    public enum StreamSelection: Sendable {
        /// Reads from a specific named stream starting at the given revision cursor.
        case specified(identifier: StreamIdentifier, cursor: RevisionCursor)
        /// Reads from the global `$all` stream starting at the given position cursor.
        case all(cursor: PositionCursor)
    }
}
