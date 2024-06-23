//
//  Stream.Identifier.swift
//
//
//  Created by Grady Zhuo on 2024/5/21.
//

@preconcurrency import Foundation
import GRPCEncapsulates

extension Stream {
    public struct Identifier: Sendable {
        typealias UnderlyingMessage = EventStore_Client_StreamIdentifier

        public let name: String
        public var encoding: String.Encoding

        public init(name: String, encoding: String.Encoding = .utf8) {
            self.name = name
            self.encoding = encoding
        }
    }
}

extension Stream.Identifier: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    public init(stringLiteral value: String) {
        self.init(name: value)
    }
}

extension Stream.Identifier {
    func build() throws -> UnderlyingMessage {
        guard let streamName = name.data(using: encoding) else {
            throw ClientError.streamNameError(message: "name: \(name), encoding: \(encoding)")
        }

        return .with {
            $0.streamName = streamName
        }
    }
}
