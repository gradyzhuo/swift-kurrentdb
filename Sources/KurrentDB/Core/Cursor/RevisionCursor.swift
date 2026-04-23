//
//  RevisionCursor.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/25.
//

/// Starting revision for reading from a named stream.
public enum RevisionCursor: Sendable {
    /// Begins reading from the first event (revision 0).
    case start
    /// Begins reading from the most recently written event.
    case end
    /// Begins reading at the explicit event revision number.
    case specified(UInt64)

    /// Creates a `specified` cursor at the given revision number.
    ///
    /// - Parameter revision: The event revision number to start from.
    /// - Returns: A `RevisionCursor.specified` case wrapping the given revision.
    public static func from(_ revision: UInt64) -> RevisionCursor {
        .specified(revision)
    }
}
