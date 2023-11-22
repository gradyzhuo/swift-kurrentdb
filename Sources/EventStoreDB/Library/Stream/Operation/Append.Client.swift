//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation

@available(macOS 10.15, *)
extension Stream.Append {
    public struct Client: StreamUnaryCall, _GRPCClient {
        internal typealias UnderlyingClient = EventStore_Client_Streams_StreamsAsyncClient
        
        public typealias UnderlyingRequest = EventStore_Client_Streams_AppendReq
        public typealias BingingResponse = Response.Success
    
        
        internal var underlyingClient: EventStore_Client_Streams_StreamsAsyncClient
        
        internal init(underlyingClient: EventStore_Client_Streams_StreamsAsyncClient) {
            self.underlyingClient = underlyingClient
        }
        
        public func call(requests: Requests) async throws -> BingingResponse {
            
            let response = try await underlyingClient.append(requests)
    
            switch response.result! {
            case .success(let successResult):
                return .init(from: successResult)
            case .wrongExpectedVersion(let wrongResult):
                throw Stream.Append.Response.Wrong.init(from: wrongResult)
            }
        }
    }
    
    
}

@available(macOS 10.15, *)
extension Stream.Append.Client {
    internal static func buildRequests(streamIdentifier: Stream.Identifier, event: EventData, options: Stream.Append.Options) throws -> Requests {
        return [
            try .with{
                $0.options = options.options
                $0.options.streamIdentifier = try streamIdentifier.build()
            },
            try .with{
                $0.proposedMessage = try event.build()
            }
        ]
    }
}

@available(macOS 10.15, *)
extension Stream.Append {
    
    public struct Response {

        public enum CurrentRevisionOption {
            case noStream
            case revision(UInt64)
        }
        
        public struct Success: UnaryResponse{
            public typealias UnderlyingMessage = EventStore_Client_Streams_AppendResp.Success
            
            
            public internal(set) var current: CurrentRevisionOption
            public internal(set) var position: Stream.Position.Option
            
            internal init(current: CurrentRevisionOption, position: Stream.Position.Option) {
                self.current = current
                self.position = position
            }
            
            internal init(from message: UnderlyingMessage) {
                let currentRevision = message.currentRevisionOption?.represented() ?? .noStream
                let position = message.positionOption?.represented() ?? .noPosition
                
                self.init(
                    current: currentRevision, position: position)
            }
            
            
        }
        
        public struct Wrong: UnaryResponse, Error {
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
            
            internal init(from message: UnderlyingMessage) {
                self.current = message.currentRevisionOption?.represented() ?? .noStream
                self.excepted = message.expectedRevisionOption?.represented() ?? .any
            }
        }
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

