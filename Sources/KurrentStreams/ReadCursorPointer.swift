//
//  ReadCursorPointer.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/24.
//

public struct CursorPointer: Sendable {
    public let revision: UInt64
    public let direction: Direction

    package init(revision: UInt64, direction: Direction) {
        self.revision = revision
        self.direction = direction
    }

    public static func forwardOn(revision: UInt64) -> Self {
        .init(revision: revision, direction: .forward)
    }

    public static func backwardFrom(revision: UInt64) -> Self {
        .init(revision: revision, direction: .backward)
    }
}
