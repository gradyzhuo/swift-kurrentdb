//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation
import GRPC

public protocol ExpectedStreamRevisionProtocol{
    static func any(_ value: EventStore_Client_Empty)->Self
    static func noStream(_ value: EventStore_Client_Empty)->Self
    static func streamExists(_ value: EventStore_Client_Empty)->Self
    static func revision(_ value: UInt64)->Self
}

extension EventStore_Client_Streams_AppendReq.Options.OneOf_ExpectedStreamRevision : ExpectedStreamRevisionProtocol {}
extension EventStore_Client_Streams_DeleteReq.Options.OneOf_ExpectedStreamRevision : ExpectedStreamRevisionProtocol {}
extension EventStore_Client_Streams_TombstoneReq.Options.OneOf_ExpectedStreamRevision : ExpectedStreamRevisionProtocol {}


@available(macOS 10.15, iOS 13, *)
public struct Stream {
    
    internal typealias UnderlyingClient = EventStore_Client_Streams_StreamsAsyncClient
    
    public static var defaultCallOptions: GRPC.CallOptions = .init()
    
    public var callOptions: GRPC.CallOptions{
        get{
            underlyingClient.defaultCallOptions
        }
        set{
            underlyingClient.defaultCallOptions = newValue
        }
    }
    
    public internal(set) var identifier: Stream.Identifier
    internal var underlyingClient: UnderlyingClient
    
    @available(macOS 13.0, *)
    public init(identifier: Stream.Identifier, channel: GRPCChannel? = nil) throws {
        let channel = channel ?? EventStore.shared.channel

        self.identifier = identifier
        self.underlyingClient = UnderlyingClient.init(channel: channel)
        
    }
    
}

@available(macOS 10.15, *)
extension Stream {
    public struct Identifier {
        typealias UnderlyingMessage = EventStore_Client_StreamIdentifier
        
        public let name: String
        public let encoding: String.Encoding = .utf8
    }
    
    public struct Position{
        public let commit: UInt64
        public let prepare: UInt64?
        
        public init(commit: UInt64, prepare: UInt64? = nil) {
            self.commit = commit
            self.prepare = prepare
        }
    }
    
    public enum Revision<Message: ExpectedStreamRevisionProtocol> {
        case any
        case noStream
        case streamExists
        case revision(UInt64)
    }
    
    public struct Duration {
        public var test: Date.Stride
    }
    
    public struct Metadata {
        var maxCount: UInt64?
        var maxAge: Duration?
        
        
    }
}



@available(macOS 10.15, *)
extension Stream.Identifier: ExpressibleByStringLiteral{
    public typealias StringLiteralType = String
    
    public init(stringLiteral value: String) {
        self.init(name: value)
    }
    
    public init(unicodeScalarLiteral value: String) {
        self.init(stringLiteral: value)
    }
    
    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(stringLiteral: value)
    }
    
}

@available(macOS 10.15, *)
extension Stream.Identifier {
    
    internal func build() throws -> UnderlyingMessage {
        guard let streamName = self.name.data(using: self.encoding) else {
            throw ClientError.streamNameError(message: "name: \(self.name), encoding: \(self.encoding)")
        }
        
        return .with{
            $0.streamName = streamName
        }
    }
}

@available(macOS 10.15, *)
extension Stream.Position {
    public enum Option {
        case noPosition
        case position(Stream.Position)
    }
    
//    public enum Commit{
//        case noPosition
//        case commit(position: UInt64)
//
//        init(message: EventStore_Client_Streams_ReadResp.ReadEvent.OneOf_Position){
//            switch message {
//            case .commitPosition(let commit):
//                self = .commit(position: commit)
//            case .noPosition(_):
//                self = .noPosition
//            }
//        }
//    }
    
    
}

@available(macOS 10.15, *)
extension Stream.Revision {
    internal func build()->Message{
        switch self {
        case .any:
            return .any(.init())
        case .noStream:
            return .noStream(.init())
        case .streamExists:
            return .streamExists(.init())
        case .revision(let rev):
            return .revision(rev)
        }
    }
}
