//
//  PositionCursor.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/25.
//

public enum PositionCursor: Sendable {
    case start
    case end
    case specified(commit: UInt64, prepare: UInt64)

    /// Returns a `specified` position cursor with both `commit` and `prepare` set to the given value.
    ///
    /// - Parameter commit: The value to use for both the `commit` and `prepare` positions.
    /// - Returns: A `PositionCursor.specified` case with identical `commit` and `prepare` values.
    public static func specified(commit: UInt64) -> Self {
        .specified(commit: commit, prepare: commit)
    }
}
