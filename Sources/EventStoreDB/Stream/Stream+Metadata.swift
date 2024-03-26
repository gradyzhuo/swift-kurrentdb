//
//  Stream+Metadata.swift
//
//
//  Created by Grady Zhuo on 2023/11/7.
//

import Foundation
import AnyCodable

//extension StreamClient {
////    public static var metadata: Stream.Metadata {
////        set {
////
////        }
////
////        get async throws {
////
////        }
////    }
//}

extension Stream {
    
    public struct Metadata: Codable {
        
        enum CodingKeys: String, CodingKey {
            case maxCount = "$maxCount"
            case maxAge = "$maxAge"
            case truncateBefore = "$tb"
            case cacheControl = "$cacheControl"
            case acl = "$acl"
            case customProperties
        }
        
        // A sliding window based on the number of items in the stream. When data reaches
        // a certain length it disappears automatically from the stream and is considered
        // eligible for scavenging.
        let maxCount: UInt64?

        // A sliding window based on dates. When data reaches a certain age it disappears
        // automatically from the stream and is considered eligible for scavenging.
        let maxAge: Duration?

        // The event number from which previous events can be scavenged. This is
        // used to implement soft-deletion of streams.
        let truncateBefore: UInt64?

        // Controls the cache of the head of a stream. Most URIs in a stream are infinitely
        // cacheable but the head by default will not cache. It may be preferable
        // in some situations to set a small amount of caching on the head to allow
        // intermediaries to handle polls (say 10 seconds).
        let cacheControl: Duration?

        // The access control list for the stream.
        let acl: Acl?

    
        // An enumerable of key-value pairs of keys to JSON value for
        // user-provided metadata.
        let customProperties: [String: AnyCodable]?
    }
}

extension Stream{
    public enum Acl: Codable{
        case userStream
        case systemStream
        case stream(StreamAcl)
    }
    
    
    public struct StreamAcl: Codable{
        
        enum CodingKeys: String, CodingKey {
            case readRoles = "$r"
            case writeRoles = "$w"
            case deleteRoles = "$d"
            case metaReadRoles = "$mr"
            case metaWriteRoles = "$mw"
        }
        
        // Roles and users permitted to read the stream.
        let readRoles: [String]?

        // Roles and users permitted to write to the stream.
        let writeRoles: [String]?

        // Roles and users permitted to delete to the stream.
        let deleteRoles: [String]?

        // Roles and users permitted to read stream metadata.
        let metaReadRoles: [String]?

        // Roles and users permitted to write stream metadata.
        let metaWriteRoles: [String]?
    }
    
}


extension Stream.StreamAcl {
    public class Builder {
        private var readRoles: [String]?
        private var writeRoles: [String]?
        private var deleteRoles: [String]?
        private var metaReadRoles: [String]?
        private var metaWriteRoles: [String]?
        
        public func add(readRole role: String) -> Self {
            readRoles = (readRoles ?? []) + [role]
            return self
        }
        
        public func add(writeRole role: String) -> Self {
            writeRoles = (writeRoles ?? []) + [role]
            return self
        }
        
        public func add(deleteRoles role: String) -> Self {
            deleteRoles = (deleteRoles ?? []) + [role]
            return self
        }
        
        public func add(metaReadRoles role: String) -> Self {
            metaReadRoles = (metaReadRoles ?? []) + [role]
            return self
        }
        
        public func add(metaWriteRoles role: String) -> Self {
            metaWriteRoles = (metaWriteRoles ?? []) + [role]
            return self
        }
        
        public func build() -> Stream.StreamAcl{
            return .init(
                readRoles: readRoles,
                writeRoles: writeRoles,
                deleteRoles: deleteRoles,
                metaReadRoles: metaReadRoles,
                metaWriteRoles: metaWriteRoles
            )
        }
        
    }
}
