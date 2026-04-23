//
//  StreamIdentifier.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/21.
//

import Foundation
import GRPCEncapsulates
import RegexBuilder

/// Identifies a KurrentDB stream by name.
///
/// Conforms to `ExpressibleByStringLiteral`, so a stream identifier can be created directly
/// from a string literal wherever the type is known.
///
/// ```swift
/// let stream: StreamIdentifier = "orders-123"
/// let stream = StreamIdentifier(name: "orders-123")
/// ```
public struct StreamIdentifier: Sendable {
    package typealias UnderlyingMessage = EventStore_Client_StreamIdentifier

    /// Stream name.
    public let name: String
    /// String encoding used when serialising the name to bytes.
    public var encoding: String.Encoding

    /// Creates a stream identifier with the given name and optional encoding.
    ///
    /// - Parameters:
    ///   - name: The stream name.
    ///   - encoding: The string encoding used when serialising the name. Defaults to `.utf8`.
    public init(name: String, encoding: String.Encoding = .utf8) {
        self.name = name
        self.encoding = encoding
    }
}

extension StreamIdentifier {
    /// Category prefix extracted from a hyphen-delimited stream name, or `nil` if none.
    ///
    /// For a stream named `"orders-123"` this returns `"orders"`.
    public var category: String? {
        let _category = Reference<String>()
        return name.prefixMatch(of: Regex {
            Capture(as: _category) {
                OneOrMore(.word)
            } transform: {
                String($0)
            }
            "-"
        })?.output.1
    }
}

extension StreamIdentifier: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self.init(name: value)
    }
}

extension StreamIdentifier: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.encoding == rhs.encoding
    }
}

extension StreamIdentifier {
    package func build() throws(KurrentError) -> UnderlyingMessage {
        guard let streamName = name.data(using: encoding) else {
            throw .internalParsingError(reason: "name coding error: \(name), encoding: \(encoding)")
        }

        return .with {
            $0.streamName = streamName
        }
    }
}

extension StreamIdentifier {
    /// Identifier for the global `$all` stream.
    public static var all: Self {
        .init(name: "$all")
    }
}
