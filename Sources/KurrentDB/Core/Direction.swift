//
//  Direction.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/25.
//

/// Read direction for stream traversal operations.
public enum Direction: Sendable {
    /// Reads events from oldest to newest.
    case forward
    /// Reads events from newest to oldest.
    case backward
}
