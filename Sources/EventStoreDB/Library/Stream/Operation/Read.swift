//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/21.
//

import Foundation
import GRPC

@available(macOS 10.15, *)
extension Stream {
    public struct Read {
        
        public struct Position{
            public let commit: UInt64
            public let prepare: UInt64
        }
        
        public enum Direction {
            case forward
            case backward
        }
        
        public enum Cursor<Pointer> {
            case start
            case end
            case at(Pointer, direction: Direction)
        }
        
        public struct Revision {
            public internal(set) var value: UInt64
        }
        
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
            
            
            internal required init(type: FilterType, window: Window = .count, prefixes: [String] = []) {
                self.type = type
                self.window = window
                self.prefixes = prefixes
            }
            
            @discardableResult
            public static func onStreamName(regex: String) -> Self {
                .init(type: .streamName(regex: regex))
            }
            
            @discardableResult
            public static func onEventType(regex: String) -> Self {
                .init(type: .eventType(regex: regex))
            }
            
            @discardableResult
            public func set(max maxCount: UInt32) -> Self {
                self.window = .max(maxCount)
                return self
            }
            
            @discardableResult
            public func add(prefix: String) -> Self {
                self.prefixes.append(prefix)
                return self
            }
            
        }
    }
}

@available(macOS 10.15, *)
extension Stream.Read.Cursor {
    
    public var direction: Stream.Read.Direction {
        get{
            switch self {
            case .start:
                return .forward
            case .end:
                return .backward
            case let .at(_, direction):
                return direction
            }
        }
    }
    
}

@available(macOS 10.15, *)
extension Stream.Read.Direction {
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options){
        switch self {
        case .forward:
            options.readDirection = .forwards
        case .backward:
            options.readDirection = .backwards
        }
    }
}

@available(macOS 10.15, *)
extension Stream.Read.Cursor where Pointer == Stream.Read.Revision{
    
    public func build( options: inout EventStore_Client_Streams_ReadReq.Options){
        switch self {
        case .start:
            options.stream.start = .init()
            options.readDirection = .forwards
        case .end:
            options.stream.end = .init()
            options.readDirection = .backwards
        case .at(let revision, let readDirection):
            options.stream.revision = revision.value
            readDirection.build(options: &options)
        }
    }
    
    public func build( options: inout EventStore_Client_Streams_ReadReq.Options.StreamOptions){
        switch self {
        case .start:
            options.start = .init()
        case .end:
            options.end = .init()
        case .at(let revision, _):
            options.revision = revision.value
        }
    }
}


@available(macOS 10.15, *)
extension Stream.Read.Revision {
    
    public func cursor(direction: Stream.Read.Direction) -> Stream.Read.Cursor<Self>{
        return .at(self, direction: direction)
    }
    
}

@available(macOS 10.15, *)
extension Stream.Read.UUIDOption{
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .structured:
            options.uuidOption.structured = .init()
        case .string:
            options.uuidOption.string = .init()
        }
    }
}


@available(macOS 10.15, *)
extension Stream.Read.ControlOption{
    internal func build(options: inout EventStore_Client_Streams_ReadReq.Options) {
        switch self {
        case .compatibility(let compatibility):
            options.controlOption.compatibility = compatibility
        }
    }
}


@available(macOS 10.15, iOS 13, *)
extension Stream.Read.Position {
    
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
    
    public func cusor(direction:  Stream.Read.Direction) -> Stream.Read.Cursor<Self> {
        return .at(self, direction: direction)
    }
}

@available(macOS 10.15, *)
extension Stream.Read.Cursor where Pointer == Stream.Read.Position{
    
    public func build() -> EventStore_Client_Streams_ReadReq.Options.AllOptions{
        .with{
            switch self {
            case .start:
                $0.start = .init()
            case .end:
                $0.end = .init()
            case let .at(position, _):
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
        case .at(let position, let readDirection):
            position.build(options: &options)
            readDirection.build(options: &options)
        }
    }
}

@available(macOS 10.15, *)
extension Stream.Read.SubscriptionFilter {
    
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

@available(macOS 10.15, *)
extension Stream.Identifier {
    
    internal func build(options: inout Stream.Read.Client.UnderlyingRequest.Options) throws{
        options.stream = try .with{
            $0.streamIdentifier = try self.build()
        }
    }
    
}
