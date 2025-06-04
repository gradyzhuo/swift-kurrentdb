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
    
    public static func specified(commit: UInt64) -> Self{
        return .specified(commit: commit, prepare: commit)
    }
}
