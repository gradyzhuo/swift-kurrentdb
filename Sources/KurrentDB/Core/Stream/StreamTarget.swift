//
//  StreamTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/3/6.
//
import Foundation

public protocol StreamTarget: Sendable {
    
}

public struct AnyStreamTarget: StreamTarget{}

public struct SpecifiedStream: StreamTarget {
    public private(set) var identifier: StreamIdentifier
    
    public init(identifier: StreamIdentifier) {
        self.identifier = identifier
    }
}

public struct AllStreams: StreamTarget {}

extension StreamTarget where Self == SpecifiedStream {
    public static func specified(_ identifier: StreamIdentifier)->SpecifiedStream{
        return .init(identifier: identifier)
    }

    public static func specified(_ name: String, encoding: String.Encoding = .utf8)->SpecifiedStream{
        return .init(identifier: .init(name: name, encoding: encoding))
    }
}

extension StreamTarget where Self == AllStreams {
    public static var all: AllStreams{
        return .init()
    }
}
