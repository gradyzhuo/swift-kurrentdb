//
//  StreamMetadata.swift
//
//
//  Created by Grady Zhuo on 2023/11/7.
//

import Foundation
import GRPCEncapsulates

public struct StreamMetadata: Buildable, Codable {
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
    var maxCount: UInt64?

    // A sliding window based on dates. When data reaches a certain age it disappears
    // automatically from the stream and is considered eligible for scavenging.
    var maxAge: Duration?

    // The event number from which previous events can be scavenged. This is
    // used to implement soft-deletion of streams.
    var truncateBefore: UInt64?

    // Controls the cache of the head of a stream. Most URIs in a stream are infinitely
    // cacheable but the head by default will not cache. It may be preferable
    // in some situations to set a small amount of caching on the head to allow
    // intermediaries to handle polls (say 10 seconds).
    var cacheControl: Duration?

    // The access control list for the stream.
    var acl: Acl?

    // An enumerable of key-value pairs of keys to JSON value for
    // user-provided metadata.
    var customProperties: [String: String]?

    public init() {
        maxCount = nil
        maxAge = nil
        truncateBefore = nil
        cacheControl = nil
        acl = nil
        customProperties = nil
    }

    public func maxCount(_ maxCount: UInt64) -> Self {
        withCopy { copied in
            copied.maxCount = maxCount
        }
    }

    public func maxAge(_ maxAge: Duration) -> Self {
        withCopy { copied in
            copied.maxAge = maxAge
        }
    }

    public func truncateBefore(_ truncateBefore: UInt64) -> Self {
        withCopy { copied in
            copied.truncateBefore = truncateBefore
        }
    }

    public func cacheControl(_ cacheControl: Duration) -> Self {
        withCopy { copied in
            copied.cacheControl = cacheControl
        }
    }

    public func acl(_ acl: Acl) -> Self {
        withCopy { copied in
            copied.acl = acl
        }
    }

    public func customProperties(_ customProperties: [String: String]) -> Self {
        withCopy { copied in
            copied.customProperties = customProperties
        }
    }

    func jsonData() throws -> Data? {
        guard let customProperties else {
            return nil
        }
        return try JSONSerialization.data(withJSONObject: customProperties)
    }
}



extension StreamMetadata {
    public enum Acl: Codable, Sendable {
        public typealias RawValue = Data

        public var rawValue: Data {
            get throws {
                let encoder = JSONEncoder()
                return switch self {
                case .userStream:
                    try encoder.encode("$userStreamAcl")
                case .systemStream:
                    try encoder.encode("$systemStreamAcl")
                case let .stream(acl):
                    try encoder.encode(acl)
                }
            }
        }

        case userStream
        case systemStream
        case stream(StreamAcl)

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let rawValue = try? container.decode(String.self) {
                if rawValue == "$userStreamAcl" {
                    self = .userStream
                } else if rawValue == "$systemStreamAcl" {
                    self = .systemStream
                } else {
                    throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: ""))
                }
            } else if let acl = try? container.decode(StreamAcl.self) {
                self = .stream(acl)
            } else {
                throw DecodingError.valueNotFound(String.self, .init(codingPath: [], debugDescription: ""))
            }
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .userStream:
                try container.encode("$userStreamAcl")
            case .systemStream:
                try container.encode("$systemStreamAcl")
            case let .stream(acl):
                try container.encode(acl)
            }
        }
    }

    public struct StreamAcl: Codable, Sendable {
        enum CodingKeys: String, CodingKey {
            case readRoles = "$r"
            case writeRoles = "$w"
            case deleteRoles = "$d"
            case metaReadRoles = "$mr"
            case metaWriteRoles = "$mw"
        }

        // Roles and users permitted to read the stream.
        public private(set) var readRoles: [String]?

        // Roles and users permitted to write to the stream.
        public private(set) var writeRoles: [String]?

        // Roles and users permitted to delete to the stream.
        public private(set) var deleteRoles: [String]?

        // Roles and users permitted to read stream metadata.
        public private(set) var metaReadRoles: [String]?

        // Roles and users permitted to write stream metadata.
        public private(set) var metaWriteRoles: [String]?
    }
}

extension StreamMetadata.StreamAcl: Buildable {
    public func readRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.readRoles = roles
        }
    }

    public func writeRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.writeRoles = roles
        }
    }

    public func deleteRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.deleteRoles = roles
        }
    }

    public func metaReadRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.metaReadRoles = roles
        }
    }

    public func metaWriteRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.metaWriteRoles = roles
        }
    }
}

extension StreamMetadata: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.cacheControl == rhs.cacheControl
            && lhs.customProperties == rhs.customProperties
            && lhs.maxAge == rhs.maxAge
            && lhs.truncateBefore == rhs.truncateBefore
            && lhs.acl == rhs.acl
    }
}

extension StreamMetadata.Acl: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        do {
            return try lhs.rawValue == rhs.rawValue
        } catch {
            logger.warning("It's failed when getting acl rawvalue of stream metadata. error: \(error)")
            return false
        }
    }
}

extension StreamMetadata.StreamAcl: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.deleteRoles == rhs.deleteRoles
            && lhs.metaReadRoles == rhs.metaReadRoles
            && lhs.metaWriteRoles == rhs.metaWriteRoles
            && lhs.readRoles == rhs.readRoles
            && lhs.writeRoles == rhs.writeRoles
    }
}
