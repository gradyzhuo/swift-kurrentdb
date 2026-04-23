//
//  SpecifiedStream.swift
//  KurrentDB
//

import Foundation

/// Target representing a single named stream.
public struct SpecifiedStream: SpecifiedStreamTarget {
    /// Unique identifier for the stream.
    public private(set) var identifier: StreamIdentifier

    init(identifier: StreamIdentifier) {
        self.identifier = identifier
    }
}

extension StreamsTarget where Self == SpecifiedStream {
    /// Creates a ``SpecifiedStream`` from an existing ``StreamIdentifier``.
    public static func specified(_ identifier: StreamIdentifier) -> SpecifiedStream {
        .init(identifier: identifier)
    }

    /// Creates a ``SpecifiedStream`` from a stream name string.
    public static func specified(_ name: String, encoding: String.Encoding = .utf8) -> SpecifiedStream {
        .init(identifier: .init(name: name, encoding: encoding))
    }
}

extension SpecifiedStream: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        identifier = .init(name: value)
    }
}
