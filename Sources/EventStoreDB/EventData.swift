//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/17.
//

import Foundation


public enum ContentType: String{
    case unknown
    case json = "application/json"
    case binary = "application/octet-stream"
}

public protocol EventStoreEvent {
    var id: UUID { get }
    var type: String { get }
    var contentType: ContentType { get }
}

public struct EventData: EventStoreEvent {
    
    public enum Content {
        case codable(Codable)
        case data(Data)
        
        public var contentType: ContentType {
            switch self {
            case .codable:
                return .json
            case .data:
                return .binary
            }
        }
        
        public var data: Data {
            get throws{
                switch self {
                case .codable(let value):
                    let encoder = JSONEncoder()
                    return try encoder.encode(value)
                case .data(let data):
                    return data
                }
            }
        }
    }
    
    public private(set) var id: UUID
    public private(set) var type: String
    public private(set) var content: Content
    public private(set) var customMetadata: [String:Codable]
    
    public var data: Data {
        get throws{
            return try content.data
        }
    }
    
    public var contentType: ContentType {
        content.contentType
    }
    
    public var metaData: [String: String] {
        [
            "content-type": self.contentType.rawValue,
            "type": type
        ]
    }
    
    public init(id: UUID, type: String, content: Content, customMetadata: [String:Codable]? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.customMetadata = customMetadata ?? [:]
    }
    
}



@available(macOS 10.15, *)
public struct RecordedEvent: EventStoreEvent {
    public private(set) var id: UUID
    public private(set) var type: String
    public private(set) var contentType: ContentType
    public private(set) var streamIdentifier: Stream.Identifier
    public private(set) var revision: UInt64
    public private(set) var position: Stream.Position
    
    public var metadata: [String:String]{
        return [
            "type": self.type,
            "content-type": self.contentType.rawValue
        ]
    }
    public private(set) var customMetadata: Data
    public private(set) var data: Data
    
    internal init(id: UUID, type: String, contentType: ContentType, streamIdentifier: Stream.Identifier, revision: UInt64, position: Stream.Position, data: Data, customMetadata: Data) {
        self.id = id
        self.type = type
        self.contentType = contentType
        self.streamIdentifier = streamIdentifier
        self.revision = revision
        self.position = position
        self.customMetadata = customMetadata
        self.data = data
    }
    
    internal init(message: EventStore_Client_Streams_ReadResp.ReadEvent.RecordedEvent) throws{
        
        guard let id = message.id.toUUID() else {
            throw ReadEventError.GRPCDecodeException(message: "RecordedEvent can't convert an UUID from message.id: \(message.id)")
        }
        
        guard let type = message.metadata["type"] else {
            throw ReadEventError.GRPCDecodeException(message: "RecordedEvent can't get an event type from message.metadata: \(message.metadata)")
        }
        
        let contentType = ContentType(rawValue: message.metadata["content-type"] ?? ContentType.binary.rawValue) ?? .unknown
        let streamIdentifier = message.streamIdentifier.toIdentifier()
        let revision = message.streamRevision
        let position = Stream.Position.init(commit: message.commitPosition, prepare: message.preparePosition)
        
        self.init(id: id, type: type, contentType: contentType, streamIdentifier: streamIdentifier, revision: revision, position: position, data: message.data, customMetadata: message.customMetadata)
        
        
    }
}

@available(macOS 10.15, *)
public struct ReadEvent {
    
    
    public private(set) var event: RecordedEvent
    public private(set) var link: RecordedEvent?
    public private(set) var commitPosition: Stream.Position?
    
    public var noPosition: Bool {
        commitPosition == nil
    }
    
    
    init(event: RecordedEvent, link: RecordedEvent? = nil, commitPosition: Stream.Position? = nil) {
        self.event = event
        self.link = link
        self.commitPosition = commitPosition
    }
    
    init(message: EventStore_Client_Streams_ReadResp.ReadEvent) throws{
        self.event = try .init(message: message.event)
        self.link = try message.hasLink ? .init(message: message.link) : nil
        
        if let position = message.position {
            switch position {
            case .noPosition(_):
                self.commitPosition = nil
            case .commitPosition(let commitPosition):
                self.commitPosition = .init(commit: commitPosition)
            }
        }else {
            self.commitPosition = nil
        }
    }
}

