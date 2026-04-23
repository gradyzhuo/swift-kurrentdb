//
//  StreamPosition.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

/// Logical position of an event in the global `$all` stream.
///
/// A position is represented as a pair of monotonically increasing integers
/// assigned by the server: `commit` and `prepare`.
public struct StreamPosition: Sendable {
    /// Commit position within the transaction log.
    public let commit: UInt64
    /// Prepare position within the transaction log.
    public let prepare: UInt64

    /// Creates a `StreamPosition` at the specified commit and prepare positions.
    ///
    /// - Parameters:
    ///   - commitPosition: The commit position in the transaction log.
    ///   - preparePosition: The prepare position in the transaction log. Defaults to `commitPosition` when omitted.
    /// - Returns: A `StreamPosition` with the given coordinates.
    public static func at(commitPosition: UInt64, preparePosition: UInt64? = nil) -> Self {
        let preparePosition = preparePosition ?? commitPosition
        return .init(commit: commitPosition, prepare: preparePosition)
    }

    private init(commit: UInt64, prepare: UInt64) {
        self.commit = commit
        self.prepare = prepare
    }
}

extension StreamPosition: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.commit == rhs.commit && lhs.prepare == rhs.prepare
    }
}
