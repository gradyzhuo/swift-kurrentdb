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
///
/// The value holds the JSON object stored in the stream's `$$<stream>` metadata stream, in
/// ``data``. The system fields are read from and written to that object, and every other key,
/// including one written by another client, is kept. Read the data of a `$$<stream>` event with
/// ``init(data:)``, as `getMetadata()` does, rather than with `JSONDecoder`: `init(from:)` keeps the
/// first occurrence of a repeated key and accepts `60.0`, which the server does not.
public struct StreamMetadata: Buildable, Codable {
    private enum Key {
        static let maxCount = "$maxCount"
        static let maxAge = "$maxAge"
        static let truncateBefore = "$tb"
        static let cacheControl = "$cacheControl"
        static let acl = "$acl"
        /// Not modelled, but checked: the server reads it as a boolean.
        static let tempStream = "$tmp"
        /// The keys of the `$acl` object.
        static let aclRoles = ["$r", "$w", "$d", "$mr", "$mw"]
    }

    /// The largest values the server applies; see the builders.
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

    /// The JSON object, exactly as stored in the stream's `$$<stream>` metadata stream.
    public private(set) var data: Data

    /// Creates a `StreamMetadata` value with all fields unset: the empty JSON object `{}`.
    public init() {
        data = Data("{}".utf8)
    }

    /// Creates a `StreamMetadata` value from the JSON stored in a stream's metadata stream.
    ///
    /// The object is checked as the server reads it, so a value is created only from metadata the
    /// server applies. The server ignores the whole object, `$acl` included, when a system key holds
    /// something it cannot read, and this initializer throws for it, as the .NET client does:
    ///
    /// - `$maxCount`, `$tb`, `$maxAge` and `$cacheControl` must be integers within `Int64`, written
    ///   without a fraction or an exponent (`60`, not `60.0` or `6e1`); `$maxAge` and
    ///   `$cacheControl` must also lie within ±922,337,203,685 seconds, .NET's `TimeSpan` range.
    ///   Zero and negative values are read: the server ignores only that field.
    /// - `$tmp` must be a boolean.
    /// - `$acl` must be an object whose keys are `$r`, `$w`, `$d`, `$mr` and `$mw`, each holding a
    ///   string or an array of strings.
    ///
    /// Other keys may hold any JSON value. Every occurrence of a repeated key is checked, as the
    /// server checks them in turn.
    ///
    /// - Parameter data: UTF-8 JSON bytes holding a top-level object. They are kept as they are,
    ///   unless an object in them repeats a key: the server reads the last occurrence of such a key,
    ///   so ``data`` then holds the object with only the last occurrence of each repeated key.
    /// - Throws: `KurrentError.internalParsingError` if `data` is not UTF-8, is not a JSON object,
    ///   nests arrays and objects more than 64 levels deep, or holds a system key the server cannot
    ///   read.
    public init(data: Data) throws(KurrentError) {
        guard JSONText.isUTF8(data) else {
            throw .internalParsingError(reason: "Stream metadata must be UTF-8 JSON, as the server stores it.")
        }
        do {
            _ = try JSONDecoder().decode([String: PropertyValue].self, from: data)
        } catch {
            throw .internalParsingError(reason: "Stream metadata must be a JSON object: \(error)")
        }
        guard let text = JSONText(data) else {
            throw .internalParsingError(reason: "Stream metadata could not be scanned, although it decodes as a JSON object.")
        }
        if let reason = Self.invalidSystemKey(in: text.root) {
            throw .internalParsingError(reason: reason)
        }
        self.data = text.keepingLastOccurrences ?? data
    }

    /// The maximum number of events retained in the stream (`$maxCount`).
    ///
    /// A sliding window based on the number of events: older events disappear from the stream
    /// and become eligible for scavenging. `nil` when the key is absent or negative, which the
    /// server ignores.
    public var maxCount: UInt64? {
        unsignedInteger(at: Key.maxCount)
    }

    /// The maximum age of events retained in the stream (`$maxAge`, in whole seconds).
    ///
    /// A sliding window based on dates: older events disappear from the stream and become
    /// eligible for scavenging. `nil` when the key is absent. A value another client stored can
    /// exceed what ``maxAge(_:)`` accepts: above 62,000,000,000 seconds it may make the stream
    /// unreadable, so do not pass it back unchecked.
    public var maxAge: Duration? {
        seconds(at: Key.maxAge)
    }

    /// The truncate-before revision (`$tb`): events before this revision are hidden from reads
    /// and later scavenged.
    ///
    /// Used to implement soft deletion of streams. `nil` when the key is absent or negative,
    /// which the server ignores.
    public var truncateBefore: UInt64? {
        unsignedInteger(at: Key.truncateBefore)
    }

    /// The cache-control duration for the stream head (`$cacheControl`, in whole seconds).
    ///
    /// The head of a stream is not cached by default; a small value lets intermediaries handle
    /// polls. `nil` when the key is absent.
    public var cacheControl: Duration? {
        seconds(at: Key.cacheControl)
    }

    /// The access control list for the stream (`$acl`).
    ///
    /// ``Acl/serverDefault`` when the object holds no `$acl`, so the server applies its default
    /// access rules; otherwise the stream's own roles, ``Acl/stream(_:)``.
    public var acl: Acl {
        guard let value = object[Key.acl] else {
            return .serverDefault
        }
        do {
            return try .stream(JSONDecoder().decode(StreamAcl.self, from: JSONEncoder().encode(value)))
        } catch {
            // `init(data:)` and `init(from:)` check `$acl`, and `acl(_:)` writes a `StreamAcl`.
            preconditionFailure("StreamMetadata.data holds an $acl the server cannot read: \(error)")
        }
    }

    /// Sets the maximum number of events retained in the stream.
    ///
    /// The server reads `$maxCount` as a signed 64-bit integer and ignores the whole metadata
    /// object, `$acl` included, when it is larger, so `maxCount` must not exceed `Int64.max`.
    /// `0` is written as it is and logged as a warning: the server ignores this field.
    ///
    /// - Precondition: `maxCount` is at most `Int64.max` (9,223,372,036,854,775,807).
    /// - Parameter maxCount: Maximum event count before older events become eligible for scavenging.
    /// - Returns: An updated copy of the metadata.
    public func maxCount(_ maxCount: UInt64) -> Self {
        precondition(maxCount <= Limit.revision, "StreamMetadata.maxCount(_:) takes at most Int64.max (\(Limit.revision)), but got \(maxCount): the server ignores the whole metadata object for a larger $maxCount.")
        if maxCount == 0 {
            logger.warning("StreamMetadata \(Key.maxCount) is 0; the server ignores this field.")
        }
        return setting([Key.maxCount: maxCount])
    }

    /// Sets the maximum age of events retained in the stream.
    ///
    /// The server stores the age in whole seconds, so any sub-second part is truncated.
    /// A duration under one second is written as it is (`0` or negative) and logged as a
    /// warning: the server ignores this field.
    ///
    /// The age must not exceed 62,000,000,000 seconds (about 1,964 years). The server subtracts
    /// it from the current time, and an age reaching back before the year 1 (about
    /// 63,900,000,000 seconds in 2026) makes every read of the stream return nothing.
    ///
    /// - Precondition: `maxAge` is at most 62,000,000,000 seconds and at least -922,337,203,685 seconds.
    /// - Parameter maxAge: Maximum age before events become eligible for scavenging.
    /// - Returns: An updated copy of the metadata.
    public func maxAge(_ maxAge: Duration) -> Self {
        setting([Key.maxAge: Self.wholeSeconds(maxAge, for: Key.maxAge, atMost: Limit.maxAge, "a longer age makes the stream unreadable")])
    }

    /// Sets the truncate-before revision: events before this revision are hidden from reads and
    /// later scavenged.
    ///
    /// The server reads `$tb` as a signed 64-bit integer and ignores the whole metadata object,
    /// `$acl` included, when it is larger, so `truncateBefore` must not exceed `Int64.max`, the
    /// value a soft delete writes.
    ///
    /// - Precondition: `truncateBefore` is at most `Int64.max` (9,223,372,036,854,775,807).
    /// - Parameter truncateBefore: Event revision acting as the soft-delete boundary.
    /// - Returns: An updated copy of the metadata.
    public func truncateBefore(_ truncateBefore: UInt64) -> Self {
        precondition(truncateBefore <= Limit.revision, "StreamMetadata.truncateBefore(_:) takes at most Int64.max (\(Limit.revision)), but got \(truncateBefore): the server ignores the whole metadata object for a larger $tb.")
        return setting([Key.truncateBefore: truncateBefore])
    }

    /// Sets the cache-control duration for the stream head.
    ///
    /// The server stores the duration in whole seconds, so any sub-second part is truncated.
    /// A duration under one second is written as it is (`0` or negative) and logged as a
    /// warning: the server ignores this field.
    ///
    /// The duration must not exceed 922,337,203,685 seconds, the longest the server can hold;
    /// it ignores the whole metadata object, `$acl` included, for a longer one.
    ///
    /// - Precondition: `cacheControl` is at most 922,337,203,685 seconds and at least -922,337,203,685 seconds.
    /// - Parameter cacheControl: Duration for which intermediaries may cache the stream head.
    /// - Returns: An updated copy of the metadata.
    public func cacheControl(_ cacheControl: Duration) -> Self {
        setting([Key.cacheControl: Self.wholeSeconds(cacheControl, for: Key.cacheControl, atMost: Limit.cacheControl, "the server ignores the whole metadata object for a longer one")])
    }

    /// Sets the access control list for the stream.
    ///
    /// ``Acl/stream(_:)`` writes the roles as the `$acl` object. ``Acl/serverDefault`` removes
    /// `$acl`, the only way to have the server apply its default access rules, and leaves every
    /// other key as it is.
    ///
    /// - Parameter acl: The `Acl` value to apply.
    /// - Returns: An updated copy of the metadata.
    public func acl(_ acl: Acl) -> Self {
        switch acl {
        case .serverDefault:
            removing(Key.acl)
        case let .stream(roles):
            setting([Key.acl: roles])
        }
    }

    /// Sets user-defined key-value metadata on the stream.
    ///
    /// Each pair is stored as a top-level string key of the metadata object, next to the system fields.
    ///
    /// - Parameter customProperties: Dictionary of string keys to string values.
    /// - Returns: An updated copy of the metadata.
    public func customProperties(_ customProperties: [String: String]) -> Self {
        setting(customProperties)
    }
}

extension StreamMetadata {
    /// The decoded JSON object.
    ///
    /// `data` always holds a JSON object: ``init(data:)`` and `init(from:)` check it, and every
    /// builder writes `JSONEncoder` output.
    private var object: [String: PropertyValue] {
        do {
            return try JSONDecoder().decode([String: PropertyValue].self, from: data)
        } catch {
            preconditionFailure("StreamMetadata.data does not hold a JSON object: \(error)")
        }
    }

    /// A copy with `values` written to their keys, every other key left as it is.
    private func setting(_ values: [String: any Codable & Sendable]) -> Self {
        withCopy { copied in
            var object = object
            do {
                for (key, value) in values {
                    object[key] = try PropertyValue(value)
                }
                copied.data = try Self.encode(object)
            } catch {
                // The values are strings, 64-bit integers and `StreamAcl`s, which always encode.
                preconditionFailure("StreamMetadata could not encode \(values.keys.sorted()): \(error)")
            }
        }
    }

    /// A copy without `key`, every other key left as it is.
    private func removing(_ key: String) -> Self {
        withCopy { copied in
            var object = object
            object[key] = nil
            do {
                copied.data = try Self.encode(object)
            } catch {
                // Every `PropertyValue` here was decoded from JSON, so it encodes.
                preconditionFailure("StreamMetadata could not encode the object without \(key): \(error)")
            }
        }
    }

    /// `duration` in whole seconds, the sub-second part truncated. It must not exceed `maximum`
    /// (`reason` says why). A result under one second is kept, but logged as a warning, because
    /// the server ignores the field.
    private static func wholeSeconds(_ duration: Duration, for key: String, atMost maximum: Int64, _ reason: String) -> Int64 {
        let seconds = duration.components.seconds
        precondition(seconds <= maximum, "StreamMetadata \(key) takes at most \(maximum) seconds, but got \(seconds) (from \(duration)): \(reason).")
        precondition(seconds >= Limit.negativeDuration, "StreamMetadata \(key) takes at least \(Limit.negativeDuration) seconds, but got \(seconds) (from \(duration)): the server reads it as a .NET TimeSpan.")
        if seconds <= 0 {
            logger.warning("StreamMetadata \(key) is \(seconds) seconds (from \(duration)); the server stores whole seconds and ignores this field when it is under one second.")
        }
        return seconds
    }

    private static func encode(_ object: [String: PropertyValue]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(object)
    }

    /// The integer at `key`, which `init(data:)` and `init(from:)` check fits in `Int64`; `nil`
    /// when it is absent or negative.
    private func unsignedInteger(at key: String) -> UInt64? {
        guard case let .integer(value) = object[key] else { return nil }
        return UInt64(exactly: value)
    }

    /// The whole seconds at `key`, which `init(data:)` and `init(from:)` check fit in `Int64`.
    private func seconds(at key: String) -> Duration? {
        guard case let .integer(value) = object[key] else { return nil }
        return .seconds(value)
    }
}

extension StreamMetadata {
    /// Why the server ignores the object `root`, or `nil` when it reads it.
    ///
    /// Mirrors the server's reader (`StreamMetadata.FromJsonReader` in KurrentDB): it reads the
    /// members in order and throws at the first system key holding a token it cannot read, so
    /// every occurrence of a repeated key is checked. Other keys are skipped whatever they hold.
    private static func invalidSystemKey(in root: JSONText.Value) -> String? {
        guard case let .object(members) = root.token else {
            return "Stream metadata must be a JSON object."
        }
        for member in members {
            let value = member.value
            if member.isNamed(Key.maxCount) || member.isNamed(Key.truncateBefore) {
                guard value.integer != nil else {
                    return invalid(member, "an integer within Int64, without a fraction or an exponent")
                }
            } else if member.isNamed(Key.maxAge) || member.isNamed(Key.cacheControl) {
                guard let seconds = value.integer, Limit.negativeDuration ... Limit.cacheControl ~= seconds else {
                    return invalid(member, "whole seconds within ±\(Limit.cacheControl), .NET's TimeSpan range, written without a fraction or an exponent")
                }
            } else if member.isNamed(Key.tempStream) {
                guard case .bool = value.token else {
                    return invalid(member, "a boolean")
                }
            } else if member.isNamed(Key.acl) {
                guard case let .object(roles) = value.token else {
                    return invalid(member, #"an object such as {"$r":["$all"]}"#)
                }
                for role in roles {
                    guard Key.aclRoles.contains(where: role.isNamed) else {
                        return "Stream metadata \(Key.acl) holds the key \(String(decoding: role.quotedName, as: UTF8.self)), which the server cannot read: \(Key.acl) may hold only \(Key.aclRoles.joined(separator: ", ")). The server ignores the whole object for it."
                    }
                    guard isRoles(role.value) else {
                        return invalid(role, "a role name or an array of role names", in: Key.acl)
                    }
                }
            }
        }
        return nil
    }

    /// Whether `value` is a string or an array of strings, the two forms of an `$acl` role list.
    private static func isRoles(_ value: JSONText.Value) -> Bool {
        switch value.token {
        case .string:
            true
        case let .array(elements):
            elements.allSatisfy { if case .string = $0.token { true } else { false } }
        default:
            false
        }
    }

    private static func invalid(_ member: JSONText.Member, _ expected: String, in parent: String? = nil) -> String {
        let key = String(decoding: member.name, as: UTF8.self)
        return "Stream metadata \(parent.map { "\($0) " } ?? "")key \(key) must hold \(expected), but holds \(member.value.excerpt()). The server ignores the whole object for it."
    }
}

extension StreamMetadata {
    /// Decodes a JSON object, every key kept as it is.
    ///
    /// The system keys are checked as ``init(data:)`` checks them, but against the values the
    /// decoder hands over, not the text: a whole number written with a fraction, such as `60.0`,
    /// passes here.
    ///
    /// To read the data of a `$$<stream>` event, use ``init(data:)``, as `getMetadata()` does, not
    /// `JSONDecoder().decode(StreamMetadata.self, from:)`: only ``init(data:)`` reads the object as
    /// the server does.
    ///
    /// - Throws: `DecodingError` if the value is not a JSON object, nests arrays and objects more
    ///   than 64 levels deep, or holds a system key the server cannot read.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let object = try container.decode([String: PropertyValue].self)
        data = try Self.encode(object)
        guard let text = JSONText(data) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Stream metadata could not be scanned after encoding.")
        }
        if let reason = Self.invalidSystemKey(in: text.root) {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: reason)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(object)
    }
}

extension StreamMetadata {
    /// Who may access a stream: the server's default access rules, or the stream's own roles.
    ///
    /// The server reads a stream's `$acl` only as an object of roles, so these are the only two
    /// forms. The names `$userStreamAcl` and `$systemStreamAcl` are not values of `$acl`: they are
    /// the keys of the `$settings` stream that hold the defaults.
    public enum Acl: Sendable, Equatable {
        /// The stream has no ACL of its own, so its metadata holds no `$acl`, and the server applies
        /// the default from the `$settings` stream: `$userStreamAcl` for a user stream and
        /// `$systemStreamAcl` for a stream whose name starts with `$`. It follows later changes to
        /// `$settings`.
        ///
        /// With the built-in defaults everyone (`$all`) may read, write and delete a user stream and
        /// read and write its metadata, and only `$admins` may access a system stream. `$all` is
        /// granted before any identity check, so it includes anonymous requests, as far as the
        /// server's settings for anonymous access allow them. Members of `$admins` always have access.
        case serverDefault
        /// The stream's own roles, stored as the `$acl` object. A permission the ``StreamAcl``
        /// leaves at ``StreamAcl/Roles/defaults`` falls back to the default from `$settings`.
        ///
        /// `.stream(.defaults)` stores the empty object, `"$acl":{}`, so every permission falls back
        /// to `$settings`: the server treats it the same as ``serverDefault``, which stores no `$acl`.
        /// ``StreamMetadata/acl`` and `==` still tell the two apart: metadata holding `"$acl":{}`
        /// reads as `.stream(.defaults)`, not `.serverDefault`.
        case stream(StreamAcl)
    }

    /// Fine-grained role-based access control for a stream: the roles of each permission.
    ///
    /// Start from ``defaults``, or from the ``StreamMetadata/acl`` already stored, and set the
    /// permissions you mean to with the builders. A permission at ``Roles/defaults`` is not stored,
    /// and the server applies the default from the `$settings` stream for it; ``Roles/granted(_:)``
    /// with an empty list grants it to no one but `$admins`.
    ///
    /// A role is a group name, such as `$admins`, `$ops` or `$all` (everyone), or a user name.
    public struct StreamAcl: Codable, Sendable, Equatable {
        enum CodingKeys: String, CodingKey {
            case readRoles = "$r"
            case writeRoles = "$w"
            case deleteRoles = "$d"
            case metaReadRoles = "$mr"
            case metaWriteRoles = "$mw"
        }

        /// Roles and users permitted to read the stream (`$r`).
        public private(set) var readRoles: Roles = .defaults

        /// Roles and users permitted to write to the stream (`$w`).
        public private(set) var writeRoles: Roles = .defaults

        /// Roles and users permitted to delete the stream (`$d`).
        public private(set) var deleteRoles: Roles = .defaults

        /// Roles and users permitted to read stream metadata (`$mr`).
        public private(set) var metaReadRoles: Roles = .defaults

        /// Roles and users permitted to write stream metadata (`$mw`).
        public private(set) var metaWriteRoles: Roles = .defaults
    }
}

extension StreamMetadata.StreamAcl {
    /// Every permission inherits the default from the `$settings` stream: stored as the empty
    /// object `{}`.
    ///
    /// `acl(.stream(.defaults))` stores `"$acl":{}`, which the server treats the same as
    /// `acl(.serverDefault)`: each permission falls back to `$settings`.
    public static let defaults = Self()

    /// The roles of one permission.
    ///
    /// An array literal is ``granted(_:)``: `writeRoles(["ops"])` stores `"$w":["ops"]`. Pass a
    /// `[String]` variable as `.granted(names)`.
    public enum Roles: ExpressibleByArrayLiteral, Sendable, Equatable {
        /// Not stored: the server applies the default from the `$settings` stream for this
        /// permission, and follows later changes to `$settings`.
        case defaults
        /// Stored as the list of roles and users. An empty list grants the permission to no one
        /// but `$admins`, whose members always have access.
        case granted([String])

        /// Creates ``granted(_:)`` with the listed roles.
        public init(arrayLiteral elements: String...) {
            self = .granted(elements)
        }

        /// The stored list, `nil` for ``defaults``.
        var stored: [String]? {
            switch self {
            case .defaults:
                nil
            case let .granted(roles):
                roles
            }
        }
    }

    /// Decodes each role entry as an array of strings or, as the server and other clients
    /// also write it, a single string. An absent entry is ``Roles/defaults``; `null` throws, since
    /// the server ignores the whole metadata for it.
    public init(from decoder: any Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readRoles = try Self.roles(in: container, forKey: .readRoles)
        writeRoles = try Self.roles(in: container, forKey: .writeRoles)
        deleteRoles = try Self.roles(in: container, forKey: .deleteRoles)
        metaReadRoles = try Self.roles(in: container, forKey: .metaReadRoles)
        metaWriteRoles = try Self.roles(in: container, forKey: .metaWriteRoles)
    }

    /// Encodes each ``Roles/granted(_:)`` entry as an array of strings and leaves out every
    /// ``Roles/defaults`` entry.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(readRoles.stored, forKey: .readRoles)
        try container.encodeIfPresent(writeRoles.stored, forKey: .writeRoles)
        try container.encodeIfPresent(deleteRoles.stored, forKey: .deleteRoles)
        try container.encodeIfPresent(metaReadRoles.stored, forKey: .metaReadRoles)
        try container.encodeIfPresent(metaWriteRoles.stored, forKey: .metaWriteRoles)
    }

    private static func roles(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Roles {
        guard container.contains(key) else {
            return .defaults
        }
        if let role = try? container.decode(String.self, forKey: key) {
            return .granted([role])
        }
        return try .granted(container.decode([String].self, forKey: key))
    }
}

extension StreamMetadata.StreamAcl: Buildable {
    /// Sets the roles permitted to read the stream (`$r`).
    ///
    /// - Parameter roles: The role and user names, or ``Roles/defaults`` to remove `$r` so the
    ///   server applies the default from `$settings`.
    /// - Returns: An updated copy of the ACL.
    public func readRoles(_ roles: Roles) -> Self {
        withCopy { copied in
            copied.readRoles = roles
        }
    }

    /// Sets the roles permitted to write to the stream (`$w`).
    ///
    /// - Parameter roles: The role and user names, or ``Roles/defaults`` to remove `$w` so the
    ///   server applies the default from `$settings`.
    /// - Returns: An updated copy of the ACL.
    public func writeRoles(_ roles: Roles) -> Self {
        withCopy { copied in
            copied.writeRoles = roles
        }
    }

    /// Sets the roles permitted to delete the stream (`$d`).
    ///
    /// - Parameter roles: The role and user names, or ``Roles/defaults`` to remove `$d` so the
    ///   server applies the default from `$settings`.
    /// - Returns: An updated copy of the ACL.
    public func deleteRoles(_ roles: Roles) -> Self {
        withCopy { copied in
            copied.deleteRoles = roles
        }
    }

    /// Sets the roles permitted to read stream metadata (`$mr`).
    ///
    /// - Parameter roles: The role and user names, or ``Roles/defaults`` to remove `$mr` so the
    ///   server applies the default from `$settings`.
    /// - Returns: An updated copy of the ACL.
    public func metaReadRoles(_ roles: Roles) -> Self {
        withCopy { copied in
            copied.metaReadRoles = roles
        }
    }

    /// Sets the roles permitted to write stream metadata (`$mw`).
    ///
    /// Keep your own user, or a role it has, in these roles: otherwise you can no longer change
    /// the metadata.
    ///
    /// - Parameter roles: The role and user names, or ``Roles/defaults`` to remove `$mw` so the
    ///   server applies the default from `$settings`.
    /// - Returns: An updated copy of the ACL.
    public func metaWriteRoles(_ roles: Roles) -> Self {
        withCopy { copied in
            copied.metaWriteRoles = roles
        }
    }
}

extension StreamMetadata: Equatable {
    /// Compares the decoded JSON objects, so key order and number spelling do not matter.
    ///
    /// The keys are compared as Swift strings, so two keys that differ only in Unicode
    /// normalization, such as `"café"` with a precomposed `é` and with `e` and a combining accent,
    /// compare equal, although the server reads them as two keys.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.object == rhs.object
    }
}
