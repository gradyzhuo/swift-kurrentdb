//
//  PositionCursor.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/25.
//

/// Starting position for reading from the `$all` stream.
public enum PositionCursor: Sendable {
    /// Begins reading from the very first event in the stream.
    case start
    /// Begins reading from the most recent event in the stream.
    case end
    /// Begins reading at the explicit commit and prepare log positions.
    case specified(commit: UInt64, prepare: UInt64)

    /// Creates a `specified` cursor with both `commit` and `prepare` set to the same value.
    ///
    /// - Parameter commit: Value used for both the commit and prepare positions.
    /// - Returns: A `PositionCursor.specified` case with identical commit and prepare positions.
    public static func specified(commit: UInt64) -> Self {
        .specified(commit: commit, prepare: commit)
    }
}
