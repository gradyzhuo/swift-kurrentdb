//
//  StreamMetadata.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2023/11/7.
//

import Foundation
import GRPCEncapsulates

/// Configuration metadata attached to a KurrentDB stream.
///
/// Controls retention, truncation, caching, and access control for a stream.
/// Use the builder methods to configure individual fields and pass the result to
/// `setStreamMetadata` on the client.
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

    /// Creates a `StreamMetadata` value with all fields unset.
    public init() {
        maxCount = nil
        maxAge = nil
        truncateBefore = nil
        cacheControl = nil
        acl = nil
        customProperties = nil
    }

    /// Sets the maximum number of events retained in the stream.
    ///
    /// - Parameter maxCount: Maximum event count before older events become eligible for scavenging.
    /// - Returns: An updated copy of the metadata.
    public func maxCount(_ maxCount: UInt64) -> Self {
        withCopy { copied in
            copied.maxCount = maxCount
        }
    }

    /// Sets the maximum age of events retained in the stream.
    ///
    /// - Parameter maxAge: Maximum age before events become eligible for scavenging.
    /// - Returns: An updated copy of the metadata.
    public func maxAge(_ maxAge: Duration) -> Self {
        withCopy { copied in
            copied.maxAge = maxAge
        }
    }

    /// Sets the event revision before which all events may be scavenged.
    ///
    /// - Parameter truncateBefore: Event revision acting as the soft-delete boundary.
    /// - Returns: An updated copy of the metadata.
    public func truncateBefore(_ truncateBefore: UInt64) -> Self {
        withCopy { copied in
            copied.truncateBefore = truncateBefore
        }
    }

    /// Sets the cache-control duration for the stream head.
    ///
    /// - Parameter cacheControl: Duration for which intermediaries may cache the stream head.
    /// - Returns: An updated copy of the metadata.
    public func cacheControl(_ cacheControl: Duration) -> Self {
        withCopy { copied in
            copied.cacheControl = cacheControl
        }
    }

    /// Sets the access control list for the stream.
    ///
    /// - Parameter acl: The `Acl` value to apply.
    /// - Returns: An updated copy of the metadata.
    public func acl(_ acl: Acl) -> Self {
        withCopy { copied in
            copied.acl = acl
        }
    }

    /// Sets user-defined key-value metadata on the stream.
    ///
    /// - Parameter customProperties: Dictionary of string keys to JSON-serialisable string values.
    /// - Returns: An updated copy of the metadata.
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
    /// Access control list applied to a stream.
    public enum Acl: Codable, Sendable {
        public typealias RawValue = Data

        /// This value encoded on its own, the way 2.6.1 and earlier wrote `$acl`.
        ///
        /// ``StreamMetadata`` writes ``userStream`` and ``systemStream`` differently, in the form the
        /// server applies; see those cases.
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

        /// Applies the server's `$userStreamAcl` from `$settings`.
        ///
        /// Written as no `$acl`, which is how the server falls back to that default, so the metadata
        /// reads back with no ACL.
        case userStream
        /// Applies the server's built-in `$systemStreamAcl`: `$admins` for every permission.
        ///
        /// Written as that ``StreamAcl``, since the server reads no reference to `$settings` in
        /// `$acl`; a `$systemStreamAcl` changed in `$settings` does not apply, and it reads back as
        /// ``stream(_:)``.
        case systemStream
        /// Applies a custom `StreamAcl` policy.
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

    /// Fine-grained role-based access control for a stream.
    public struct StreamAcl: Codable, Sendable {
        enum CodingKeys: String, CodingKey {
            case readRoles = "$r"
            case writeRoles = "$w"
            case deleteRoles = "$d"
            case metaReadRoles = "$mr"
            case metaWriteRoles = "$mw"
        }

        /// Roles and users permitted to read the stream.
        public private(set) var readRoles: [String]?

        /// Roles and users permitted to write to the stream.
        public private(set) var writeRoles: [String]?

        /// Roles and users permitted to delete the stream.
        public private(set) var deleteRoles: [String]?

        /// Roles and users permitted to read stream metadata.
        public private(set) var metaReadRoles: [String]?

        /// Roles and users permitted to write stream metadata.
        public private(set) var metaWriteRoles: [String]?
    }
}

extension StreamMetadata.StreamAcl: Buildable {
    /// Sets the roles permitted to read the stream.
    ///
    /// - Parameter roles: Array of role or username strings.
    /// - Returns: An updated copy of the ACL.
    public func readRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.readRoles = roles
        }
    }

    /// Sets the roles permitted to write to the stream.
    ///
    /// - Parameter roles: Array of role or username strings.
    /// - Returns: An updated copy of the ACL.
    public func writeRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.writeRoles = roles
        }
    }

    /// Sets the roles permitted to delete the stream.
    ///
    /// - Parameter roles: Array of role or username strings.
    /// - Returns: An updated copy of the ACL.
    public func deleteRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.deleteRoles = roles
        }
    }

    /// Sets the roles permitted to read stream metadata.
    ///
    /// - Parameter roles: Array of role or username strings.
    /// - Returns: An updated copy of the ACL.
    public func metaReadRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.metaReadRoles = roles
        }
    }

    /// Sets the roles permitted to write stream metadata.
    ///
    /// - Parameter roles: Array of role or username strings.
    /// - Returns: An updated copy of the ACL.
    public func metaWriteRoles(_ roles: [String]) -> Self {
        withCopy { copied in
            copied.metaWriteRoles = roles
        }
    }
}

// The server reads `$$<stream>` with its own parser and ignores the whole object when one
// system key has the wrong shape, so `$maxCount`, `$tb` and `$acl` written next to it are never
// applied. These implementations write the shapes the server reads, and read both those and
// the ones 2.6.1 and earlier wrote.
extension StreamMetadata {
    /// The largest values the server applies.
    private enum Limit {
        /// `$maxCount` and `$tb`: the server reads them as `Int64`.
        static let revision = UInt64(Int64.max)
        /// `$maxAge` in seconds: a longer age reaches back before the year 1 (about
        /// 63,900,000,000 seconds in 2026) and makes the stream unreadable. Rounded down, so the
        /// limit holds for every date from now on.
        static let maxAge: Int64 = 62_000_000_000
        /// `$cacheControl` in seconds: .NET's `TimeSpan.MaxValue`.
        static let cacheControl: Int64 = 922_337_203_685
        /// `$maxAge` and `$cacheControl` below zero: .NET's `TimeSpan.MinValue` in seconds.
        static let negativeDuration: Int64 = -922_337_203_685
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxCount = try container.decodeIfPresent(UInt64.self, forKey: .maxCount)
        maxAge = try Self.decodeDuration(from: container, forKey: .maxAge)
        truncateBefore = try container.decodeIfPresent(UInt64.self, forKey: .truncateBefore)
        cacheControl = try Self.decodeDuration(from: container, forKey: .cacheControl)
        acl = try container.decodeIfPresent(Acl.self, forKey: .acl)
        customProperties = try container.decodeIfPresent([String: String].self, forKey: .customProperties)
    }

    /// Writes the object the server applies.
    ///
    /// - `$maxAge` and `$cacheControl` are whole seconds; a sub-second part is dropped.
    /// - ``Acl/userStream`` writes no `$acl`, so the server applies its `$userStreamAcl` default.
    /// - ``Acl/systemStream`` writes `$admins` for every permission, the server's built-in
    ///   `$systemStreamAcl`; a `$systemStreamAcl` changed in `$settings` does not apply.
    ///
    /// - Throws: `EncodingError.invalidValue` for a value the server would ignore the whole
    ///   object for: `maxCount` or `truncateBefore` above `Int64.max`, `maxAge` above
    ///   62,000,000,000 seconds, `cacheControl` above 922,337,203,685 seconds, or either duration
    ///   below -922,337,203,685 seconds.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(Self.revision(maxCount, forKey: .maxCount), forKey: .maxCount)
        try container.encodeIfPresent(Self.wholeSeconds(maxAge, forKey: .maxAge, atMost: Limit.maxAge), forKey: .maxAge)
        try container.encodeIfPresent(Self.revision(truncateBefore, forKey: .truncateBefore), forKey: .truncateBefore)
        try container.encodeIfPresent(Self.wholeSeconds(cacheControl, forKey: .cacheControl, atMost: Limit.cacheControl), forKey: .cacheControl)
        switch acl {
        case .none, .userStream:
            break
        case .systemStream:
            try container.encode(StreamAcl.systemStreamDefault, forKey: .acl)
        case let .stream(streamAcl):
            try container.encode(streamAcl, forKey: .acl)
        }
        try container.encodeIfPresent(customProperties, forKey: .customProperties)
    }

    /// Whole seconds, or the `Duration` array 2.6.1 and earlier wrote; `null` reads as unset, as
    /// it did in 2.6.1.
    private static func decodeDuration(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Duration? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else {
            return nil
        }
        if let seconds = try? container.decode(Int64.self, forKey: key) {
            return .seconds(seconds)
        }
        return try container.decode(Duration.self, forKey: key)
    }

    private static func revision(_ value: UInt64?, forKey key: CodingKeys) throws -> UInt64? {
        guard let value else {
            return nil
        }
        guard value <= Limit.revision else {
            throw EncodingError.invalidValue(value, .init(codingPath: [key], debugDescription: "StreamMetadata \(key.rawValue) takes at most \(Limit.revision), but got \(value): the server reads it as Int64 and ignores the whole metadata otherwise."))
        }
        return value
    }

    private static func wholeSeconds(_ duration: Duration?, forKey key: CodingKeys, atMost maximum: Int64) throws -> Int64? {
        guard let duration else {
            return nil
        }
        let seconds = duration.components.seconds
        guard (Limit.negativeDuration ... maximum).contains(seconds) else {
            throw EncodingError.invalidValue(duration, .init(codingPath: [key], debugDescription: "StreamMetadata \(key.rawValue) takes \(Limit.negativeDuration) to \(maximum) seconds, but got \(seconds) (from \(duration)): the server ignores the whole metadata otherwise."))
        }
        if seconds <= 0 {
            logger.warning("StreamMetadata \(key.rawValue) is \(seconds) seconds (from \(duration)); the server stores whole seconds and ignores this field when it is under one second.")
        }
        return seconds
    }
}

extension StreamMetadata.StreamAcl {
    /// The server's built-in `$systemStreamAcl`: `$admins` for every permission.
    static let systemStreamDefault = Self()
        .readRoles(["$admins"])
        .writeRoles(["$admins"])
        .deleteRoles(["$admins"])
        .metaReadRoles(["$admins"])
        .metaWriteRoles(["$admins"])

    /// Reads each permission as the server does: a single role string or an array of them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readRoles = try Self.roles(in: container, forKey: .readRoles)
        writeRoles = try Self.roles(in: container, forKey: .writeRoles)
        deleteRoles = try Self.roles(in: container, forKey: .deleteRoles)
        metaReadRoles = try Self.roles(in: container, forKey: .metaReadRoles)
        metaWriteRoles = try Self.roles(in: container, forKey: .metaWriteRoles)
    }

    private static func roles(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> [String]? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else {
            return nil
        }
        if let role = try? container.decode(String.self, forKey: key) {
            return [role]
        }
        return try container.decode([String].self, forKey: key)
    }
}

extension StreamMetadata: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.maxCount == rhs.maxCount
            && lhs.cacheControl == rhs.cacheControl
            && lhs.customProperties == rhs.customProperties
            && lhs.maxAge == rhs.maxAge
            && lhs.truncateBefore == rhs.truncateBefore
            && lhs.acl == rhs.acl
    }
}

extension StreamMetadata.Acl: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.userStream, .userStream), (.systemStream, .systemStream):
            true
        case let (.stream(lhs), .stream(rhs)):
            lhs == rhs
        default:
            false
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
