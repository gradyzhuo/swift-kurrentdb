//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation

@available(macOS 10.15, *)
extension Stream.Read {
    public struct Client: UnaryStreamCall, _GRPCClient {
        
        internal typealias UnderlyingClient = EventStore_Client_Streams_StreamsAsyncClient
        
        public typealias UnderlyingRequest = EventStore_Client_Streams_ReadReq
        public typealias BingingResponse = Response
        
        internal var underlyingClient: EventStore_Client_Streams_StreamsAsyncClient
        
        internal init(underlyingClient: UnderlyingClient) {
            self.underlyingClient = underlyingClient
        }
        
        public func call(request: EventStore_Client_Streams_ReadReq) throws -> Responses {
            
            let responses = underlyingClient.read(request)
            return Responses { continuation in
                Task {
                    for try await result in responses {
                        guard let content = result.content else {
                            throw ClientError.readResponseError(message: "content not found in response: \(result)")
                        }
                        continuation.yield(try BingingResponse.init(content: content))
                    }
                    continuation.finish()
                }
            }
        }
        
    }
}


@available(macOS 10.15, *)
extension Stream.Read.Client {
    
    internal static func buildRequest(streamIdentifier: Stream.Identifier, cursor: Stream.Read.Cursor<Stream.Read.Revision>, options: Stream.Read.Options) throws -> UnderlyingRequest {
        
        var options = options.options
        options.stream.streamIdentifier = try streamIdentifier.build()
        cursor.build(options: &options)

        return .with{
            $0.options = options
        }
    }
    
    internal static func buildRequest(cursor: Stream.Read.Cursor<Stream.Read.Position>, options: Stream.Read.Options) throws -> UnderlyingRequest {
        
        return UnderlyingRequest.with{
            $0.options = options.options
            cursor.build(options: &$0.options)
        }
    }
}

@available(macOS 10.15, *)
extension Stream.Read {
    
    public struct Response: GRPCBridge {
        
        public enum Content {
            case event(ReadEvent)
            case confirmation(subscription: String)
            case checkpoint(position: Stream.Position)
            case streamNotFound(streamName: String)
            case commitPosition(firstStream: UInt64)
            case commitPosition(lastStream: UInt64)
            case position(lastAllStream: Stream.Position)
            case caughtUp
            case fellBehind
        }
        
        public typealias UnderlyingMessage = EventStore_Client_Streams_ReadResp
        
        public var content: Content
        
        init(content: Content){
            self.content = content
        }
        
        init(message: UnderlyingMessage.ReadEvent) throws {
            self.content = try .event(.init(message: message))
        }
        
        init(message: UnderlyingMessage.SubscriptionConfirmation) {
            self.content = .confirmation(subscription: message.subscriptionID)
        }
        
        init(message: UnderlyingMessage.Checkpoint) {
            self.content = .checkpoint(position: .init(commit: message.commitPosition, prepare: message.preparePosition))
        }
        
        init(message: UnderlyingMessage.StreamNotFound) throws {
            
            guard let streamName = String(data: message.streamIdentifier.streamName, encoding: .utf8) else {
                throw ClientError.streamNameError(message: "\(message)")
            }
            
            self.content = .streamNotFound(streamName: streamName)
        }
        
        init(firstStreamPosition commitPosition: UInt64) {
            self.content = .commitPosition(firstStream: commitPosition)
        }
        
        init(lastStreamPosition commitPosition: UInt64) {
            self.content = .commitPosition(lastStream: commitPosition)
        }
        
        init(message: EventStore_Client_AllStreamPosition) {
            self.content = .position(lastAllStream: .init(commit: message.commitPosition, prepare: message.preparePosition))
        }
        
        init(message: UnderlyingMessage.CaughtUp) {
            self.content = .caughtUp
        }
        
        init(message: UnderlyingMessage.FellBehind) {
            self.content = .fellBehind
        }
        
        init(content: UnderlyingMessage.OneOf_Content) throws {
            
            switch content {
            case .event(let value):
                try self.init(message: value)
            case .confirmation(let value):
                self.init(message: value)
            case .checkpoint(let value):
                self.init(message: value)
            case .streamNotFound(let value):
                try self.init(message: value)
            case .firstStreamPosition(let value):
                self.init(firstStreamPosition: value)
            case .lastStreamPosition(let value):
                self.init(lastStreamPosition: value)
            case .lastAllStreamPosition(let value):
                self.init(message: value)
            case .caughtUp(let value):
                self.init(message: value)
            case .fellBehind(let value):
                self.init(message: value)
            }
            
        }
        
    }
}


@available(macOS 10.15, *)
extension Stream.Read.Response.Content {
    internal init(content: EventStore_Client_Streams_ReadResp.OneOf_Content) throws{
        switch content {
        case .event(let message):
            self = try .event(.init(message: message))
        case .caughtUp(_):
            self = .caughtUp
        case .checkpoint(let point):
            let position:Stream.Position = .init(commit: point.commitPosition, prepare: point.preparePosition)
            self = .checkpoint(position: position)
        case .confirmation(let confirmation):
            let subscription = confirmation.subscriptionID
            self = .confirmation(subscription: subscription)
        case .firstStreamPosition(let position):
            self = .commitPosition(firstStream: position)
        case .lastStreamPosition(let position):
            self = .commitPosition(lastStream: position)
        case .lastAllStreamPosition(let p):
            let position: Stream.Position = .init(commit: p.commitPosition, prepare: p.preparePosition)
            self = .position(lastAllStream: position)
        case .fellBehind(_):
            self = .fellBehind
        case .streamNotFound(let notFoundIdentifier):
            let streamName: String = .init(data: notFoundIdentifier.streamIdentifier.streamName, encoding: .utf8)!
            self = .streamNotFound(streamName: streamName)
        }
        
    }
    
}
