//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/21.
//

import Foundation
import GRPC
import GRPCSupport

@available(macOS 13.0, *)
extension StreamClient {
    public struct Read: UnaryStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Streams_ReadReq>
        
        public typealias CursorPointer = (UInt64, direction: StreamClient.Read.Direction)
        
        public let streamIdentifier: StreamClient.Identifier
        public let cursor: StreamClient.Cursor<CursorPointer>
        public let options: Options
        
        
        init(streamIdentifier: StreamClient.Identifier, cursor: StreamClient.Cursor<CursorPointer>, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.cursor = cursor
            self.options = options
            
        }
    
        public func build() throws -> Request.UnderlyingMessage {
            return try .with{
                $0.options = options.build()
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
                cursor.build(options: &$0.options)
            }
        }
        
    }
    
    public struct ReadAll: UnaryStream {
        public typealias Options = StreamClient.Read.Options
        public typealias Request = StreamClient.Read.Request
        public typealias Response = StreamClient.Read.Response
        
        public typealias CursorPointer = (StreamClient.Read.Position, direction: StreamClient.Read.Direction)
        
        public let cursor: StreamClient.Cursor<CursorPointer>
        public let options: Options
        
        
        init(cursor: StreamClient.Cursor<CursorPointer>, options: Options) {
            self.cursor = cursor
            self.options = options
            
        }
    
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.options
                cursor.build(options: &$0.options)
            }
        }
        
    }
}

@available(macOS 13.0, *)
extension StreamClient.Read {
    public struct Position{
        public let commit: UInt64
        public let prepare: UInt64
    }
    
    public enum Direction {
        case forward
        case backward
    }
    
//    public enum Cursor<Pointer> {
//        case start
//        case end
//        case at(Pointer, direction: Direction)
//    }
    
//    public struct Revision {
//        public internal(set) var value: UInt64
//    }
//    
    public enum UUIDOption {
        case structured
        case string
    }
    
    
    public enum ControlOption {
        case compatibility(UInt32)
    }
    
    public class SubscriptionFilter {
        
        public enum Window {
            case count
            case max(UInt32)
        }
        
        public enum FilterType {
            case streamName(regex: String)
            case eventType(regex: String)
        }
        
        public internal(set) var type: FilterType
        public internal(set) var window: Window
        public internal(set) var prefixes: [String]
        public internal(set) var checkpointIntervalMultiplier: UInt32
        
        
        internal required init(type: FilterType, window: Window = .count, prefixes: [String] = []) {
            self.type = type
            self.window = window
            self.prefixes = prefixes
            self.checkpointIntervalMultiplier = .max
        }
        
        @discardableResult
        public static func onStreamName(regex: String) -> Self {
            return .init(type: .streamName(regex: regex))
        }
        
        @discardableResult
        public static func onEventType(regex: String) -> Self {
            return .init(type: .eventType(regex: regex))
        }
        
        @discardableResult
        public func set(max maxCount: UInt32) -> Self {
            self.window = .max(maxCount)
            return self
        }
        
        @discardableResult
        public func set(checkpointIntervalMultiplier multiplier: UInt32) -> Self {
            self.checkpointIntervalMultiplier = multiplier
            return self
        }
        
        @discardableResult
        public func add(prefix: String) -> Self {
            self.prefixes.append(prefix)
            return self
        }
        
    }
}

@available(macOS 13.0, *)
extension StreamClient.Cursor where Pointer == StreamClient.Read.CursorPointer {
    
    internal var direction: StreamClient.Read.Direction {
        get{
            switch self {
            case .start:
                return .forward
            case .end:
                return .backward
            case let .at((_, direction)):
                return direction
            }
        }
    }
    
}

@available(macOS 13.0, *)
extension StreamClient.Read.Direction {
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options){
        switch self {
        case .forward:
            options.readDirection = .forwards
        case .backward:
            options.readDirection = .backwards
        }
    }
}


@available(macOS 13.0, *)
extension StreamClient.Cursor where Pointer == StreamClient.Read.CursorPointer{
    public func build( options: inout EventStore_Client_Streams_ReadReq.Options){
        switch self {
        case .start:
            options.stream.start = .init()
            options.readDirection = .forwards
        case .end:
            options.stream.end = .init()
            options.readDirection = .backwards
        case .at(let (revision, readDirection)):
            options.stream.revision = revision
            readDirection.build(options: &options)
        }
    }
    
    public func build( options: inout EventStore_Client_Streams_ReadReq.Options.StreamOptions){
        switch self {
        case .start:
            options.start = .init()
        case .end:
            options.end = .init()
        case .at(let (revision, _)):
            options.revision = revision
        }
    }
}

//@available(macOS 13.0, *)
//extension Stream.Read.Revision {
//    
//    public func cursor(direction: Stream.Read.Direction) -> Stream.Read.Cursor<Self>{
//        return .at(self, direction: direction)
//    }
//    
//}

@available(macOS 13.0, *)
extension StreamClient.Read.UUIDOption{
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .structured:
            options.uuidOption.structured = .init()
        case .string:
            options.uuidOption.string = .init()
        }
    }
}


@available(macOS 13.0, *)
extension StreamClient.Read.ControlOption{
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .compatibility(let compatibility):
            options.controlOption.compatibility = compatibility
        }
    }
}


@available(macOS 13.0, *)
extension StreamClient.Read.Position {
    
    internal func build() -> EventStore_Client_Streams_ReadReq.Options.Position{
        return .with{
            $0.commitPosition = commit
            $0.preparePosition = prepare
        }
    }
    
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options){
        options.all.position = .with{
            $0.commitPosition = commit
            $0.preparePosition = prepare
        }
    }
    
    public func cusor(direction:  StreamClient.Read.Direction) -> StreamClient.Cursor<StreamClient.ReadAll.CursorPointer> {
        return .at((self, direction: direction))
    }
}

@available(macOS 13.0, *)
extension StreamClient.Cursor where Pointer == StreamClient.ReadAll.CursorPointer{
    
    public func build() -> EventStore_Client_Streams_ReadReq.Options.AllOptions{
        .with{
            switch self {
            case .start:
                $0.start = .init()
            case .end:
                $0.end = .init()
            case let .at((position, _)):
                $0.position = position.build()
            }
        }
    }
    
    public func build(options: inout EventStore_Client_Streams_ReadReq.Options){
        switch self {
        case .start:
            options.all.start = .init()
            options.readDirection = .forwards
        case .end:
            options.all.end = .init()
            options.readDirection = .backwards
        case .at(let (position, readDirection)):
            position.build(options: &options)
            readDirection.build(options: &options)
        }
    }
}

@available(macOS 13.0, *)
extension StreamClient.Read.SubscriptionFilter {
    
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options){
        options.filter = .with{
            
            switch self.type {
            case .streamName(let regex):
                $0.streamIdentifier = .with{
                    $0.regex = regex
                    $0.prefix = self.prefixes
                }
            
            case .eventType(let regex):
                $0.eventType = .with{
                    $0.regex = regex
                    $0.prefix = self.prefixes
                }
            }
            
            
        }
    }
}

@available(macOS 13.0, *)
extension StreamClient.Identifier {
    
    internal func build(options: inout StreamClient.Read.Options.UnderlyingMessage) throws{
        options.stream = try .with{
            $0.streamIdentifier = try self.build()
        }
    }
    
}


@available(macOS 13.0, *)
extension StreamClient.Read {
    
    public struct Response: GRPCResponse {
        
        public enum Content {
            case event(readEvent: ReadEvent)
            case confirmation(subscription: String)
            case checkpoint(position: StreamClient.Position)
            case streamNotFound(streamName: String)
            case commitPosition(firstStream: UInt64)
            case commitPosition(lastStream: UInt64)
            case position(lastAllStream: StreamClient.Position)
            case caughtUp
            case fellBehind
        }
        
        public typealias UnderlyingMessage = EventStore_Client_Streams_ReadResp
        
        public var content: Content
        
        init(content: Content){
            self.content = content
        }
        
        public init(from message: EventStore_Client_Streams_ReadResp) throws {
            guard let content = message.content else {
                throw ClientError.readResponseError(message: "content not found in response: \(message)")
            }
            try self.init(content: content)
        }
        
        init(message: UnderlyingMessage.ReadEvent) throws {
            self.content = try .event(readEvent: .init(message: message))
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


@available(macOS 13.0, *)
extension StreamClient.Read.Response.Content {
    internal init(content: EventStore_Client_Streams_ReadResp.OneOf_Content) throws{
        switch content {
        case .event(let message):
            self = try .event(readEvent: .init(message: message))
        case .caughtUp(_):
            self = .caughtUp
        case .checkpoint(let point):
            let position:StreamClient.Position = .init(commit: point.commitPosition, prepare: point.preparePosition)
            self = .checkpoint(position: position)
        case .confirmation(let confirmation):
            let subscription = confirmation.subscriptionID
            self = .confirmation(subscription: subscription)
        case .firstStreamPosition(let position):
            self = .commitPosition(firstStream: position)
        case .lastStreamPosition(let position):
            self = .commitPosition(lastStream: position)
        case .lastAllStreamPosition(let p):
            let position: StreamClient.Position = .init(commit: p.commitPosition, prepare: p.preparePosition)
            self = .position(lastAllStream: position)
        case .fellBehind(_):
            self = .fellBehind
        case .streamNotFound(let notFoundIdentifier):
            let streamName: String = .init(data: notFoundIdentifier.streamIdentifier.streamName, encoding: .utf8)!
            self = .streamNotFound(streamName: streamName)
        }
        
    }
    
}
