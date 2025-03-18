//
//  PositionCursor.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/18.
//

public protocol StreamsCursor: Sendable {
    
}

public struct StartRevision: StreamsCursor {
    let direction: Direction
}

public struct EndRevision: StreamsCursor {
    let direction: Direction
}

public struct SpecifiedRevision: StreamsCursor {
    let revision: Revision
    let direction: Direction
}


extension StreamsCursor where Self == StartRevision {
    public static func start(direction: Direction = .forward)->Self{
        return .init(direction: direction)
    }
}

extension StreamsCursor where Self == EndRevision {
    public static func end(direction: Direction = .backward)->Self{
        return .init(direction: direction)
    }
}

extension StreamsCursor where Self == SpecifiedRevision {
    public static func from(revision: UInt64, direction: Direction = .forward)->Self{
        return .init(revision: .init(revision), direction: direction)
    }
}



func test(cursor: StreamsCursor){
    test(cursor: .from(revision: 60, direction: .backward))
}

