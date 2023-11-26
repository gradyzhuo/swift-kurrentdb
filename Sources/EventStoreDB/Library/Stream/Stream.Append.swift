//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/22.
//

import Foundation
import GRPC

@available(macOS 10.15, *)
extension Stream {
    public struct Append: StreamUnary {        
        public let event: EventData
        public let options: Options
        public let streamIdentifier: Stream.Identifier
        
        
        internal init(streamIdentifier: Stream.Identifier, event: EventData, options: Options){
            self.event = event
            self.options = options
            self.streamIdentifier = streamIdentifier
        }
        
        public func build() throws -> [Request.UnderlyingMessage] {
            return [
                try .with{
                    $0.options = options.build()
                    $0.options.streamIdentifier = try self.streamIdentifier.build()
                },
                try .with{
                    $0.proposedMessage = try event.build()
                }
            ]
        }
        
    }
}

@available(macOS 10.15, *)
extension Stream.Append {
    
    public enum CurrentRevisionOption {
        case noStream
        case revision(UInt64)
    }
    
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_Streams_AppendReq
        
        
    }
    
    public enum Response: GRPCResponse {
        
        public enum CurrentRevisionOption {
            case noStream
            case revision(UInt64)
            
            public var revision: UInt64? {
                get {
                    return switch self {
                    case .revision(let rev): rev
                    case .noStream: nil
                    }
                }
            }
        }
        
        public typealias UnderlyingMessage = EventStore_Client_Streams_AppendResp
        
        case success(Success)
        case wrong(Wrong)

        public init(from message: UnderlyingMessage) throws {
            switch message.result! {
            case .success(let successResult):
                self = .success(try .init(from: successResult))
            case .wrongExpectedVersion(let wrongResult):
                self = .wrong(Stream.Append.Response.Wrong.init(from: wrongResult))
            }
        }
        
        
        public struct Success: GRPCResponse{
            public typealias UnderlyingMessage = EventStore_Client_Streams_AppendResp.Success
        
            public internal(set) var current: CurrentRevisionOption
            public internal(set) var position: Stream.Position.Option
            
            internal init(current: CurrentRevisionOption, position: Stream.Position.Option) {
                self.current = current
                self.position = position
            }
            
            public init(from message: UnderlyingMessage) throws {
                let currentRevision = message.currentRevisionOption?.represented() ?? .noStream
                let position = message.positionOption?.represented() ?? .noPosition
                
                self.init(
                    current: currentRevision, position: position)
            }
            
            
        }
        
        public struct Wrong: GRPCResponse, Error {
            public typealias UnderlyingMessage = EventStore_Client_Streams_AppendResp.WrongExpectedVersion
            
            public enum ExpectedRevisionOption {
                case any
                case streamExists
                case noStream
                case revision(UInt64)
            }
            
            public internal(set) var current: CurrentRevisionOption
            public internal(set) var excepted: ExpectedRevisionOption
            
            
            internal init(current: CurrentRevisionOption, excepted: ExpectedRevisionOption) {
                self.current = current
                self.excepted = excepted
            }
            
            public init(from message: UnderlyingMessage) {
                self.current = message.currentRevisionOption?.represented() ?? .noStream
                self.excepted = message.expectedRevisionOption?.represented() ?? .any
            }
        }
    }
}

@available(macOS 10.15, *)
extension Stream.Identifier {
    
    internal func build(options: inout Stream.Append.Request.UnderlyingMessage.Options) throws{
        options.streamIdentifier = try self.build()
    }
}

extension EventData {
    
    internal func build(request: inout EventStore_Client_Streams_AppendReq) throws {
        request.proposedMessage = try .with{
            $0.id = .with{
                $0.value = .string(self.id.uuidString)
            }
            
            $0.data = try content.data
            $0.metadata = self.metaData
        }
    }
    
    internal func build() throws -> EventStore_Client_Streams_AppendReq.ProposedMessage{
        return try .with{
            $0.id = .with{
                $0.value = .string(id.uuidString)
            }
            
            $0.data = try content.data
            $0.metadata = metaData
        }
    }
}
