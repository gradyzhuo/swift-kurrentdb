//
//  StreamPosition.swift
//
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

public struct StreamPosition: Sendable {
    public let commit: UInt64
    public let prepare: UInt64

    public static func at(commitPosition: UInt64, preparePosition: UInt64? = nil) -> Self {
        let preparePosition = preparePosition ?? commitPosition
        return .init(commit: commitPosition, prepare: preparePosition)
    }

    private init(commit: UInt64, prepare: UInt64) {
        self.commit = commit
        self.prepare = prepare
    }
}


extension StreamPosition {
    public enum Option: Sendable {
        case noPosition
        case position(StreamPosition)
        
        public var value: StreamPosition?{
            return switch self {
            case .noPosition:
               nil
            case let .position(value):
                value
            }
        }
    }
}

extension StreamPosition: Equatable{
    public static func == (lhs: StreamPosition, rhs: StreamPosition) -> Bool {
        return lhs.commit == rhs.commit && lhs.prepare == rhs.prepare
    }
}
