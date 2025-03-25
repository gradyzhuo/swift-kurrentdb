//
//  PositionCursor.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/25.
//

public enum PositionCursor: Sendable {
    case start
    case end
    case position(commit: UInt64, prepare: UInt64)
    
    public static func position(commit: UInt64) -> Self{
        return .position(commit: commit, prepare: commit)
    }
}
