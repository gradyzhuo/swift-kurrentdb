//
//  Stream.Revision.swift
//
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation

extension Stream {
    public struct Revision: Sendable {
        public private(set) var value: UInt64

        public init(_ value: UInt64) {
            self.value = value
        }
    }
}

extension Stream.Revision: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = UInt64

    public init(integerLiteral value: UInt64) {
        self.value = value
    }
}
