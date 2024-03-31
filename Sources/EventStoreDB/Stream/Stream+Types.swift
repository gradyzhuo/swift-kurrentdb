//
//  Stream+Types.swift
//
//
//  Created by Grady Zhuo on 2023/11/23.
//

import Foundation
import GRPC
import GRPCSupport

public protocol ExpectedStreamRevisionProtocol {
    static func any(_ value: EventStore_Client_Empty) -> Self
    static func noStream(_ value: EventStore_Client_Empty) -> Self
    static func streamExists(_ value: EventStore_Client_Empty) -> Self
    static func revision(_ value: UInt64) -> Self
}

extension EventStore_Client_Streams_AppendReq.Options.OneOf_ExpectedStreamRevision: ExpectedStreamRevisionProtocol {}
extension EventStore_Client_Streams_DeleteReq.Options.OneOf_ExpectedStreamRevision: ExpectedStreamRevisionProtocol {}
extension EventStore_Client_Streams_TombstoneReq.Options.OneOf_ExpectedStreamRevision: ExpectedStreamRevisionProtocol {}


public struct Stream{
    
    
    
    public struct Identifier: Sendable {
        typealias UnderlyingMessage = EventStore_Client_StreamIdentifier

        public let name: String
        public let encoding: String.Encoding = .utf8
    }
    
    public struct Revision: ExpressibleByIntegerLiteral{
        public typealias IntegerLiteralType = UInt64
        
        var value: IntegerLiteralType
        
        public init(_ value: IntegerLiteralType) {
            self.value = value
        }
        
        public init(integerLiteral value: UInt64) {
            self.value = value
        }
    }
    
    

    public struct Position: Sendable {
        public let commit: UInt64
        public let prepare: UInt64

        public init(commit: UInt64, prepare: UInt64? = nil) {
            self.commit = commit
            self.prepare = prepare ?? commit
        }
    }

    public enum RevisionRule {
        case any
        case noStream
        case streamExists
        case revision(UInt64)
    }
    
    public enum Selection {
        case all
        case specified(identifier: Stream.Identifier)
        
        public static func specified(name: String)->Self{
            return .specified(identifier: .init(name: name))
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

extension Stream.Position {
    public enum Option {
        case noPosition
        case position(Stream.Position)
    }
}


