//
//  EventData.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCEncapsulates

public struct EventData: EventStoreEvent{
    public enum Content : Sendable{
        case binary(Data)
        case json(Codable & Sendable)
        
        internal var contentType: String {
            switch self {
            case .binary:
                return "application/octet-stream"
            case .json:
                return "application/json"
            }
        }
        
        package var data: Data {
            get throws{
                switch self {
                case .binary(let data):
                    return data
                case .json(let json):
                    return try JSONEncoder().encode(json)
                }
            }
        }
        
    }
    public private(set) var id: UUID
    public private(set) var eventType: String
    public private(set) var payload: Content
    public private(set) var customMetadata: Data?
    
    public private(set) var metadata: [String: String]
    
//    public init(id: UUID = .init(), eventType: String, payload: Content, contentType: ContentType, customMetadata: Data? = nil) {
//        self.id = id
//        self.eventType = eventType
//        self.content = content
//        self.contentType = contentType
//        metadata = [
//            "content-type": ContentType.json.rawValue,
//            "type": eventType,
//        ]
//        self.customMetadata = customMetadata
//    }
    
    public init(id: UUID = .init(), eventType: String, payload: Content, contentType: ContentType, customMetadata: Data? = nil) {
        self.id = id
        self.eventType = eventType
        self.payload = payload
        self.customMetadata = customMetadata
        
        self.metadata = [
            "content-type": payload.contentType,
            "type": eventType
        ]
    }
    
    public init(id: UUID = .init(), eventType: String, payload: Codable & Sendable, customMetadata: Data? = nil) {
        self.init(id: id, eventType: eventType, payload: .json(payload), contentType: .json, customMetadata: customMetadata)
    }
}


