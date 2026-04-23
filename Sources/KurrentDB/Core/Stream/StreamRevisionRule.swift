//
//  StreamRevisionRule.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

/// Optimistic concurrency rule applied when appending events to a stream.
public enum StreamRevision: Sendable {
    /// No concurrency check — always append regardless of the current revision.
    case any
    /// Requires the stream to not yet exist.
    case noStream
    /// Requires the stream to already exist.
    case streamExists
    /// Requires the stream's last event to be at the specified revision number.
    case at(UInt64)
}
