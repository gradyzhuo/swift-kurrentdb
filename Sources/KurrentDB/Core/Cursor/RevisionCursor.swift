//
//  RevisionCursor.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/25.
//

public enum RevisionCursor: Sendable {
    case start
    case end
    case specified(UInt64)
}
