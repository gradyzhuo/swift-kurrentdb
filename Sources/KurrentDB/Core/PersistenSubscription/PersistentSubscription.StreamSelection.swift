//
//  PersistentSubscription.StreamSelection.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    /// Identifies which stream a persistent subscription reads from.
    public enum StreamSelection {
        /// Reads from the global `$all` stream, optionally starting at a position and applying a filter.
        case all(position: PositionCursor, filterOption: StreamFilter? = nil)
        /// Reads from a specific named stream starting at the given revision.
        case specified(identifier: StreamIdentifier, revision: RevisionCursor)

        public static func specified(identifier: StreamIdentifier) -> Self {
            .specified(identifier: identifier, revision: .end)
        }

        public static func specified(streamName: String, revision: RevisionCursor = .end) -> Self {
            .specified(identifier: .init(name: streamName), revision: revision)
        }
    }
}
