//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/21.
//

import Foundation
import GRPCEncapsulates

extension Stream {
    
    public struct Identifier {
        typealias UnderlyingMessage = EventStore_Client_StreamIdentifier
        
        public let name: String
        public var encoding: String.Encoding = .utf8
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
