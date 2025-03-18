//
//  ReadCursorPointer.swift
//  KurrentStreams
//
//  Created by 卓俊諺 on 2025/1/24.
//

public struct Revision {
    public private(set) var value: UInt64
    
    public init(_ value: UInt64) {
        self.value = value
    }
}

extension Revision: ExpressibleByIntegerLiteral{
    public typealias IntegerLiteralType = UInt64
    
    public init(integerLiteral value: UInt64) {
        self.init(value)
    }
}
