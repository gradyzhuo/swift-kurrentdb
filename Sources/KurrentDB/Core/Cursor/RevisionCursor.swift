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
    
    public static func from(_ revision: UInt64) -> RevisionCursor {
        .specified(revision)
    }
}
