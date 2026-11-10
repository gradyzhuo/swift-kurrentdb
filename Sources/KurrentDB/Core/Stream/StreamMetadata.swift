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
/// `setMetadata(metadata:expectedRevision:)` on a stream; `getMetadata()` returns what is stored.
///
/// The value holds the system fields (``maxCount``, ``maxAge``, ``truncateBefore``,
/// ``cacheControl`` and ``acl``) and every other key of the JSON object stored in the stream's
/// `$$<stream>` metadata stream, including one written by another client or a `$` key a later
/// server adds, so a builder never drops a key it does not set.
///
/// ``maxAge`` and ``cacheControl`` are stored in whole seconds, as the server reads them, so a
/// sub-second part is truncated. Keys starting with `$` are reserved for the server; custom keys
/// sit next to them at the top level of the object.
///
/// The JSON is read and written as the server reads it, which `JSONDecoder` and `JSONEncoder` do
/// not: `StreamMetadata` is neither `Decodable` nor `Encodable`. Read the data of a `$$<stream>`
/// event with ``init(data:)``, as `getMetadata()` does, and print `String(reflecting:)` to see the
/// JSON `setMetadata(metadata:expectedRevision:)` sends. See <doc:Stream-metadata>.
public struct StreamMetadata: Buildable {
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

    /// A key the type does not model: a custom key, `$tmp`, or a `$` key a later server adds.
    struct Member: Sendable {
        let key: String
        var value: Value

        enum Value: Sendable {
            /// Read from the server: the JSON another client wrote, rewritten as standard JSON
            /// with every digit of every number kept.
            case read([UInt8])
            /// Set through a builder.
            case written(PropertyValue)
        }
    }

    // The system fields as the server reads them: an Int64 integer token, whole seconds for the
    // durations. Named apart from the public properties they back.
    private var storedMaxCount: Int64?
    private var storedMaxAge: Int64?
    private var storedTruncateBefore: Int64?
    private var storedCacheControl: Int64?
    private var storedAcl: StreamAcl?
    /// Every other key, in the order it is written.
    private var others: [Member] = []

    /// Creates a `StreamMetadata` value with all fields unset: the empty JSON object `{}`.
    public init() {}

    /// Creates a `StreamMetadata` value from the JSON stored in a stream's metadata stream.
    ///
    /// The JSON is read as the server reads it, so a value is created only from metadata the
    /// server applies. The server ignores the whole object, `$acl` included, when it cannot read
    /// it, and this initializer throws for it, as the .NET client does:
    ///
    /// - `$maxCount`, `$tb`, `$maxAge` and `$cacheControl` must be integers within `Int64`, written
    ///   without a fraction or an exponent (`60`, not `60.0` or `6e1`); `$maxAge` and
    ///   `$cacheControl` must also lie within ±922,337,203,685 seconds, .NET's `TimeSpan` range.
    ///   Zero and negative values are read: the server ignores only that field.
    /// - `$tmp` must be a boolean.
    /// - `$acl` must be an object whose keys are `$r`, `$w`, `$d`, `$mr` and `$mw`, each holding a
    ///   role name or an array of role names. A role name that reads as a date, such as
    ///   `"2024-01-01T00:00:00"`, is refused: the server's JSON reader turns it into a date.
    /// - A string anywhere in the object must not read as a date outside the years 1 to 9999, such
    ///   as `"/Date(253402300800000)/"`: the server's JSON reader fails on it.
    ///
    /// Other keys may hold any JSON value. Every occurrence of a repeated key is checked, as the
    /// server checks them in turn, and the last one is read.
    ///
    /// The server reads JSON with Newtonsoft.Json, which accepts more than standard JSON: single
    /// quotes, unquoted keys, octal and hexadecimal integers (`010` is 8), `NaN`, `Infinity`,
    /// `undefined`, trailing commas, and comments inside the value of a custom key. All of it is
    /// read here the same way. A custom value is kept as standard JSON with every digit of every
    /// number, so writing the metadata back does not change it. The server stops reading at the
    /// object's closing brace, so anything after it is ignored and not kept.
    ///
    /// - Parameter data: The JSON bytes: UTF-8, or UTF-16 or UTF-32 with a byte order mark.
    /// - Throws: `KurrentError.internalParsingError` if the server would ignore the object: it is
    ///   not a JSON object, nests arrays and objects more than 64 levels deep, or holds a value
    ///   the server cannot read.
    public init(data: Data) throws(KurrentError) {
        do {
            self = try KurrentJSONDecoder().decode(Self.self, from: data)
        } catch {
            throw .internalParsingError(reason: "Stream metadata the server ignores: \(error)")
        }
    }

    /// The maximum number of events retained in the stream (`$maxCount`).
    ///
    /// A sliding window based on the number of events: older events disappear from the stream
    /// and become eligible for scavenging. `nil` when the key is absent or negative, which the
    /// server ignores.
    public var maxCount: UInt64? {
        storedMaxCount.flatMap { UInt64(exactly: $0) }
    }

    /// The maximum age of events retained in the stream (`$maxAge`, in whole seconds).
    ///
    /// A sliding window based on dates: older events disappear from the stream and become
    /// eligible for scavenging. `nil` when the key is absent. A value another client stored can
    /// exceed what ``maxAge(_:)`` accepts: above 62,000,000,000 seconds it may make the stream
    /// unreadable, so do not pass it back unchecked.
    public var maxAge: Duration? {
        storedMaxAge.map { .seconds($0) }
    }

    /// The truncate-before revision (`$tb`): events before this revision are hidden from reads
    /// and later scavenged.
    ///
    /// Used to implement soft deletion of streams. `nil` when the key is absent or negative,
    /// which the server ignores.
    public var truncateBefore: UInt64? {
        storedTruncateBefore.flatMap { UInt64(exactly: $0) }
    }

    /// The cache-control duration for the stream head (`$cacheControl`, in whole seconds).
    ///
    /// The head of a stream is not cached by default; a small value lets intermediaries handle
    /// polls. `nil` when the key is absent.
    public var cacheControl: Duration? {
        storedCacheControl.map { .seconds($0) }
    }

    /// The access control list for the stream (`$acl`).
    ///
    /// ``Acl/serverDefault`` when the object holds no `$acl`, so the server applies its default
    /// access rules; otherwise the stream's own roles, ``Acl/stream(_:)``.
    public var acl: Acl {
        storedAcl.map(Acl.stream) ?? .serverDefault
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
            logger.warning("StreamMetadata \(Keys.maxCount.stringValue) is 0; the server ignores this field.")
        }
        return withCopy { $0.storedMaxCount = Int64(maxCount) }
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
        let seconds = Self.wholeSeconds(maxAge, for: Keys.maxAge, atMost: Limit.maxAge, "a longer age makes the stream unreadable")
        return withCopy { $0.storedMaxAge = seconds }
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
        return withCopy { $0.storedTruncateBefore = Int64(truncateBefore) }
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
        let seconds = Self.wholeSeconds(cacheControl, for: Keys.cacheControl, atMost: Limit.cacheControl, "the server ignores the whole metadata object for a longer one")
        return withCopy { $0.storedCacheControl = seconds }
    }

    /// Sets the access control list for the stream.
    ///
    /// ``Acl/stream(_:)`` writes the roles as the `$acl` object. ``Acl/serverDefault`` removes
    /// `$acl`, the only way to have the server apply its default access rules, and leaves every
    /// other key as it is.
    ///
    /// A role name must not read as a date to the server's JSON reader, such as
    /// `"2024-01-01T00:00:00"`: `setMetadata(metadata:expectedRevision:)` throws for it, because
    /// the server would ignore the whole metadata object.
    ///
    /// - Parameter acl: The `Acl` value to apply.
    /// - Returns: An updated copy of the metadata.
    public func acl(_ acl: Acl) -> Self {
        withCopy { copied in
            switch acl {
            case .serverDefault:
                copied.storedAcl = nil
            case let .stream(roles):
                copied.storedAcl = roles
            }
        }
    }

    /// Sets user-defined key-value metadata on the stream.
    ///
    /// Each pair is stored as a top-level string key of the metadata object, next to the system fields.
    /// A key starting with `$` is reserved for the server, so it is skipped and logged as a warning;
    /// ``customProperties(encoding:)`` throws for it instead.
    ///
    /// - Parameter customProperties: Dictionary of string keys to string values.
    /// - Returns: An updated copy of the metadata.
    @available(*, deprecated, message: "use customProperties(encoding:). Removed in 4.0.")
    public func customProperties(_ customProperties: [String: String]) -> Self {
        let reserved = customProperties.keys.filter(Self.isReserved)
        if !reserved.isEmpty {
            logger.warning("StreamMetadata.customProperties(_:) skipped the reserved keys \(reserved.sorted()); custom keys must not start with '$'.")
        }
        return setting(customProperties.filter { !Self.isReserved($0.key) }.mapValues(PropertyValue.string))
    }

    /// Decodes the custom keys, every key not starting with `$`, into `T`.
    ///
    /// The system keys (`$maxCount`, `$acl`, ...) and any other `$` key are left out before decoding,
    /// so `T` never sees them, and a `[String: V]` dictionary holds only the custom keys.
    /// `JSONDecoder` uses its default strategies, so a `Date` field expects seconds since 2001-01-01
    /// and `Data` expects Base64.
    ///
    /// - Parameter type: The type the custom keys decode into, such as a `Decodable` struct.
    /// - Returns: The decoded value.
    /// - Throws: `KurrentError.internalParsingError` if the custom keys do not decode as `T`.
    public func customProperties<T: Decodable>(as type: T.Type) throws(KurrentError) -> T {
        do {
            var object: [[UInt8]] = []
            for member in others where !Self.isReserved(member.key) {
                var bytes: [UInt8] = []
                KurrentJSONValue.write(member.key, to: &bytes)
                bytes.append(UInt8(ascii: ":"))
                try object.append(bytes + member.value.json)
            }
            return try JSONDecoder().decode(type, from: Data([UInt8(ascii: "{")] + object.joined(separator: [UInt8(ascii: ",")]) + [UInt8(ascii: "}")]))
        } catch {
            throw .internalParsingError(reason: "The custom stream metadata does not decode as \(type): \(error)")
        }
    }

    /// Decodes the value of one custom key into `T`.
    ///
    /// Only custom keys are read: a key starting with `$` returns `nil`, like an absent key.
    /// Read the system fields through their properties, such as ``maxCount``.
    ///
    /// The value is decoded with `JSONDecoder` from standard JSON, so a `Decimal` gets every
    /// digit. A value only the server's JSON reader understands, `NaN`, `Infinity` or
    /// `undefined`, throws.
    ///
    /// - Parameters:
    ///   - key: The custom key. Two keys that differ only in Unicode normalization are the same
    ///     key here, as Swift compares strings.
    ///   - type: The type its value decodes into, such as `String`, `Int` or a `Decodable` struct.
    /// - Returns: The decoded value, or `nil` when the key is absent or starts with `$`.
    /// - Throws: `KurrentError.internalParsingError` if the value does not decode as `T`.
    public func customProperty<T: Decodable>(_ key: String, as type: T.Type) throws(KurrentError) -> T? {
        guard !Self.isReserved(key), let member = others.first(where: { $0.key == key }) else {
            return nil
        }
        do {
            return try JSONDecoder().decode(type, from: Data(member.value.json))
        } catch {
            throw .internalParsingError(reason: "The custom stream metadata key '\(key)' does not decode as \(type): \(error)")
        }
    }

    /// Merges the top-level keys of an encoded value into the metadata object as custom keys.
    ///
    /// The value is encoded with `JSONEncoder`, so a nested struct, a number, a boolean or an array
    /// is stored as the JSON it encodes to. A key the metadata already holds is replaced; keys the
    /// value does not hold are left as they are.
    ///
    /// `JSONEncoder` uses its default strategies: a `Date` is stored as seconds since 2001-01-01 and
    /// `Data` as Base64. Encode such fields yourself (an ISO 8601 string, for example) when other
    /// clients read them.
    ///
    /// - Parameter value: A value that encodes to a JSON object, such as a `Codable` struct or a dictionary.
    /// - Returns: An updated copy of the metadata.
    /// - Throws: `KurrentError.encodingError` if the value cannot be encoded, does not encode to a
    ///   JSON object, holds a key starting with `$`, which is reserved for the server, or nests
    ///   arrays and objects more than 64 levels deep, the value itself being the first level.
    public func customProperties(encoding value: some Encodable & Sendable) throws(KurrentError) -> Self {
        guard case let .object(values) = try Self.propertyValue(encoding: value) else {
            throw .encodingError(message: "Custom stream metadata must encode to a JSON object, but \(type(of: value)) does not.", encoding: .utf8)
        }
        let reserved = values.keys.filter(Self.isReserved)
        guard reserved.isEmpty else {
            throw .encodingError(message: "Custom stream metadata keys must not start with '$': \(reserved.sorted()).", encoding: .utf8)
        }
        return setting(values)
    }

    /// Sets one custom key to an encoded value.
    ///
    /// The value is encoded with `JSONEncoder`, so it may be any JSON value: a string, a number, a
    /// boolean, an array, an object or null.
    ///
    /// - Parameters:
    ///   - key: The custom key. It must not start with `$`, which is reserved for the server. A key
    ///     the metadata holds in another Unicode normalization is replaced, as Swift compares strings.
    ///   - value: The value to store.
    /// - Returns: An updated copy of the metadata.
    /// - Throws: `KurrentError.encodingError` if `key` starts with `$`, if `JSONEncoder` rejects
    ///   the value (a NaN or infinite number, for example), or if the value nests arrays and objects
    ///   more than 63 levels deep: with the metadata object around it, the stored JSON may nest at
    ///   most 64 levels.
    public func customProperty(_ key: String, encoding value: some Encodable & Sendable) throws(KurrentError) -> Self {
        guard !Self.isReserved(key) else {
            throw .encodingError(message: "Custom stream metadata key '\(key)' must not start with '$'.", encoding: .utf8)
        }
        let encoded = try Self.propertyValue(encoding: value)
        // The metadata object is the first level, so the value may take the remaining ones.
        guard encoded.depth < PropertyValue.maximumDepth else {
            throw .encodingError(message: "Custom stream metadata key '\(key)' nests \(encoded.depth) levels deep; with the metadata object around it, the stored JSON may nest at most \(PropertyValue.maximumDepth) levels.", encoding: .utf8)
        }
        return setting([key: encoded])
    }
}

extension StreamMetadata.Member.Value {
    /// The value as standard JSON.
    var json: [UInt8] {
        get throws {
            switch self {
            case let .read(json):
                return json
            case let .written(value):
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
                return try Array(encoder.encode(value))
            }
        }
    }
}

extension StreamMetadata {
    /// A copy with each custom key in `values` set, every other key left as it is.
    ///
    /// Keys are compared as `String`s, as `==` compares them: a key replaces every spelling of it
    /// the metadata holds, where the first one stands. New keys are appended in sorted order.
    private func setting(_ values: [String: PropertyValue]) -> Self {
        withCopy { copied in
            for (key, value) in values.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }) {
                let index = copied.others.firstIndex { $0.key == key } ?? copied.others.endIndex
                copied.others.removeAll { $0.key == key }
                copied.others.insert(Member(key: key, value: .written(value)), at: min(index, copied.others.endIndex))
            }
        }
    }

    /// Whether `key` is reserved for the server: a system field such as `$maxCount`, or a future one.
    private static func isReserved(_ key: String) -> Bool {
        key.hasPrefix("$")
    }

    /// `value` encoded with `JSONEncoder` and read back as a JSON value.
    private static func propertyValue(encoding value: some Encodable) throws(KurrentError) -> PropertyValue {
        do {
            return try JSONDecoder().decode(PropertyValue.self, from: JSONEncoder().encode(value))
        } catch {
            throw .encodingError(message: "Custom stream metadata of type \(type(of: value)) cannot be encoded: \(error)", encoding: .utf8)
        }
    }

    /// `duration` in whole seconds, the sub-second part truncated. It must not exceed `maximum`
    /// (`reason` says why). A result under one second is kept, but logged as a warning, because
    /// the server ignores the field.
    private static func wholeSeconds(_ duration: Duration, for key: Keys, atMost maximum: Int64, _ reason: String) -> Int64 {
        let seconds = duration.components.seconds
        precondition(seconds <= maximum, "StreamMetadata \(key.stringValue) takes at most \(maximum) seconds, but got \(seconds) (from \(duration)): \(reason).")
        precondition(seconds >= Limit.negativeDuration, "StreamMetadata \(key.stringValue) takes at least \(Limit.negativeDuration) seconds, but got \(seconds) (from \(duration)): the server reads it as a .NET TimeSpan.")
        if seconds <= 0 {
            logger.warning("StreamMetadata \(key.stringValue) is \(seconds) seconds (from \(duration)); the server stores whole seconds and ignores this field when it is under one second.")
        }
        return seconds
    }
}

// MARK: - JSON as the server reads it

extension StreamMetadata: KurrentJSONCodable {
    /// The keys of the metadata object, with what the server's `FromJsonReader` requires of each.
    struct Keys: KurrentJSONCodingKey {
        let stringValue: String

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue _: Int) {
            nil
        }

        var intValue: Int? {
            nil
        }

        static let maxCount = Keys(stringValue: "$maxCount")
        static let maxAge = Keys(stringValue: "$maxAge")
        static let truncateBefore = Keys(stringValue: "$tb")
        static let cacheControl = Keys(stringValue: "$cacheControl")
        static let acl = Keys(stringValue: "$acl")

        /// The server skips a key it does not know.
        static let rejectsUnknownKeys = false

        /// Keyed by the UTF-8 bytes, as the server compares keys: a `String` key would also match
        /// a canonically equivalent spelling.
        private static let requirements: [[UInt8]: KurrentJSONRequirement] = [
            Array("$maxCount".utf8): .integer(.min ... .max),
            Array("$tb".utf8): .integer(.min ... .max),
            Array("$maxAge".utf8): .integer(Limit.negativeDuration ... Limit.cacheControl),
            Array("$cacheControl".utf8): .integer(Limit.negativeDuration ... Limit.cacheControl),
            // Not modelled, but checked: the server reads it as a boolean.
            Array("$tmp".utf8): .boolean,
            Array("$acl".utf8): .object,
        ]

        var requirement: KurrentJSONRequirement {
            Self.requirements[Array(stringValue.utf8)] ?? .any
        }

        /// Whether the key is stored in its own field rather than in `others`.
        var isModelled: Bool {
            [Self.maxCount, .maxAge, .truncateBefore, .cacheControl, .acl]
                .contains { $0.stringValue.utf8.elementsEqual(stringValue.utf8) }
        }
    }

    init(from container: KurrentJSONDecodingContainer<Keys>) throws {
        // Every occurrence was checked against its requirement when the container was built.
        storedMaxCount = try container.decodeIfPresent(Int64.self, forKey: .maxCount)
        storedMaxAge = try container.decodeIfPresent(Int64.self, forKey: .maxAge)
        storedTruncateBefore = try container.decodeIfPresent(Int64.self, forKey: .truncateBefore)
        storedCacheControl = try container.decodeIfPresent(Int64.self, forKey: .cacheControl)
        storedAcl = try container.decodeIfPresent(StreamAcl.self, forKey: .acl)
        others = container.members { !$0.isModelled }.map { Member(key: $0.key, value: .read($0.json)) }
    }

    func encode(to container: inout KurrentJSONEncodingContainer<Keys>) throws {
        try container.encodeIfPresent(storedMaxCount, forKey: .maxCount)
        try container.encodeIfPresent(storedMaxAge, forKey: .maxAge)
        try container.encodeIfPresent(storedTruncateBefore, forKey: .truncateBefore)
        try container.encodeIfPresent(storedCacheControl, forKey: .cacheControl)
        try container.encodeIfPresent(storedAcl, forKey: .acl)
        for member in others {
            let key = Keys(stringValue: member.key)
            switch member.value {
            case let .read(json):
                container.encode(json: json, forKey: key)
            case let .written(value):
                try container.encodeIfPresent(value, forKey: key)
            }
        }
    }

    /// The JSON `setMetadata(metadata:expectedRevision:)` sends: the system fields first, then
    /// every other key in the order it was read or set.
    ///
    /// - Throws: ``KurrentError/encodingError(message:encoding:)`` if the server would ignore the
    ///   object: an `$acl` role name, or a string in a custom value, reads as a date to the
    ///   server's JSON reader.
    func encoded() throws(KurrentError) -> Data {
        do {
            return try KurrentJSONEncoder().encode(self)
        } catch {
            throw .encodingError(message: "Stream metadata the server would ignore: \(error)", encoding: .utf8)
        }
    }
}

extension StreamMetadata: CustomDebugStringConvertible {
    /// The JSON `setMetadata(metadata:expectedRevision:)` sends, or why it cannot be sent.
    public var debugDescription: String {
        do {
            return try String(decoding: encoded(), as: UTF8.self)
        } catch {
            return "StreamMetadata(\(error))"
        }
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
    public struct StreamAcl: Sendable, Equatable {

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
}

extension StreamMetadata.StreamAcl: KurrentJSONCodable {
    /// The keys of the `$acl` object, as the server's `ReadAcl` reads them.
    enum Keys: String, KurrentJSONCodingKey {
        case readRoles = "$r"
        case writeRoles = "$w"
        case deleteRoles = "$d"
        case metaReadRoles = "$mr"
        case metaWriteRoles = "$mw"

        /// `ReadRoles`: a role name, or an array of role names.
        var requirement: KurrentJSONRequirement {
            .either(.string, .array(of: .string))
        }

        /// `ReadAcl` has no default case: after an unknown key it reads the key's value where it
        /// expects the next key, and fails.
        static let rejectsUnknownKeys = true
    }

    /// Reads each role entry as an array of strings or, as the server and other clients also
    /// write it, a single string. An absent entry is ``Roles/defaults``.
    init(from container: KurrentJSONDecodingContainer<Keys>) throws {
        self.init()
        readRoles = try Self.roles(in: container, forKey: .readRoles)
        writeRoles = try Self.roles(in: container, forKey: .writeRoles)
        deleteRoles = try Self.roles(in: container, forKey: .deleteRoles)
        metaReadRoles = try Self.roles(in: container, forKey: .metaReadRoles)
        metaWriteRoles = try Self.roles(in: container, forKey: .metaWriteRoles)
    }

    /// Writes each ``Roles/granted(_:)`` entry as an array of strings and leaves out every
    /// ``Roles/defaults`` entry.
    func encode(to container: inout KurrentJSONEncodingContainer<Keys>) throws {
        try container.encodeIfPresent(readRoles.stored, forKey: .readRoles)
        try container.encodeIfPresent(writeRoles.stored, forKey: .writeRoles)
        try container.encodeIfPresent(deleteRoles.stored, forKey: .deleteRoles)
        try container.encodeIfPresent(metaReadRoles.stored, forKey: .metaReadRoles)
        try container.encodeIfPresent(metaWriteRoles.stored, forKey: .metaWriteRoles)
    }

    /// The server's `ReadRoles` reads a single string as a list of one, so `"a"` and `["a"]` are
    /// the same roles. This holds only for the five keys of `$acl`.
    private static func roles(in container: KurrentJSONDecodingContainer<Keys>, forKey key: Keys) throws -> Roles {
        guard container.contains(key) else {
            return .defaults
        }
        // The requirement allowed only a string or an array of strings.
        if let role = try? container.decodeIfPresent(String.self, forKey: key) {
            return .granted([role])
        }
        return try .granted(container.decodeIfPresent([String].self, forKey: key) ?? [])
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
    /// Compares the metadata as it is read, so key order and number spelling (`10`, `1e1`) do not
    /// matter.
    ///
    /// `$acl` is compared as the roles the server reads, so a role written `"a"` equals one
    /// written `["a"]`; the value of every other key is compared as it is written. Custom keys are
    /// compared as Swift strings, so two keys that differ only in Unicode normalization, such as
    /// `"café"` with a precomposed `é` and with `e` and a combining accent, are one key, and the
    /// first one is compared.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.storedMaxCount == rhs.storedMaxCount
            && lhs.storedMaxAge == rhs.storedMaxAge
            && lhs.storedTruncateBefore == rhs.storedTruncateBefore
            && lhs.storedCacheControl == rhs.storedCacheControl
            && lhs.storedAcl == rhs.storedAcl
            && lhs.comparableOthers == rhs.comparableOthers
    }

    private var comparableOthers: [String: ComparableValue] {
        Dictionary(others.map { ($0.key, ComparableValue($0.value)) }, uniquingKeysWith: { first, _ in first })
    }
}

/// A custom value as `==` compares it: `PropertyValue`'s shape, which reads `10` and `1e1` as the
/// same number, plus what only the server's JSON reader understands.
private indirect enum ComparableValue: Equatable {
    case scalar(PropertyValue)
    case array([ComparableValue])
    case object([String: ComparableValue])
    /// `NaN`, `Infinity`, `-Infinity` or `undefined`.
    case literal(String)
    /// A number `JSONDecoder` cannot hold, such as `1e400`, as its significant digits and a
    /// power of ten, so `1e400` equals `10e399`. The exponent is kept as signed decimal digits:
    /// the server's reader accepts one of any length.
    case decimal(isNegative: Bool, digits: [UInt8], exponent: SignedDigits)
    case constructor(name: String, arguments: [ComparableValue])

    init(_ value: StreamMetadata.Member.Value) {
        switch value {
        case let .written(value):
            self.init(value)
        case let .read(json):
            if let value = try? JSONDecoder().decode(PropertyValue.self, from: Data(json)) {
                self.init(value)
            } else {
                // Holds something JSON cannot express. The JSON was scanned when it was read.
                var scanner = KurrentJSONScanner(utf8: json)
                self = (try? scanner.scanValue()).map(ComparableValue.init) ?? .literal(String(decoding: json, as: UTF8.self))
            }
        }
    }

    init(_ value: PropertyValue) {
        switch value {
        case let .array(values):
            self = .array(values.map(ComparableValue.init))
        case let .object(fields):
            self = .object(fields.mapValues(ComparableValue.init))
        default:
            self = .scalar(value)
        }
    }

    init(_ value: KurrentJSONValue) {
        switch value.token {
        case let .object(members):
            // As `JSONDecoder` reads a dictionary: of keys equal as strings, the first.
            self = .object(Dictionary(members.map { ($0.key, ComparableValue($0.value)) }, uniquingKeysWith: { first, _ in first }))
        case let .array(values):
            self = .array(values.map(ComparableValue.init))
        case let .constructor(name, arguments):
            self = .constructor(name: name, arguments: arguments.map(ComparableValue.init))
        case let .string(text, _):
            self = .scalar(.string(text))
        case let .bool(value):
            self = .scalar(.bool(value))
        case .null:
            self = .scalar(.null)
        case .undefined:
            self = .literal("undefined")
        case let .number(number):
            if let value = try? JSONDecoder().decode(PropertyValue.self, from: Data(number.text.utf8)) {
                self = .scalar(value)
            } else {
                self = ComparableValue(number: number.text)
            }
        }
    }

    /// A number in standard JSON that `JSONDecoder` cannot hold, or a non-finite literal.
    private init(number text: String) {
        let digits = UInt8(ascii: "0") ... UInt8(ascii: "9")
        var rest = Array(text.utf8)[...]
        let isNegative = rest.first == UInt8(ascii: "-")
        if isNegative {
            rest = rest.dropFirst()
        }
        guard let first = rest.first, digits ~= first else {
            self = .literal(text)
            return
        }
        let whole = rest.prefix(while: digits.contains)
        rest = rest.dropFirst(whole.count)
        var fraction = ArraySlice<UInt8>()
        if rest.first == UInt8(ascii: ".") {
            fraction = rest.dropFirst().prefix(while: digits.contains)
            rest = rest.dropFirst(fraction.count + 1)
        }
        // What is left is empty or `e`, an optional sign and digits.
        let exponent = SignedDigits(rest.dropFirst())
        var significant = Array((whole + fraction).drop { $0 == UInt8(ascii: "0") })
        var trailingZeros = 0
        while significant.last == UInt8(ascii: "0") {
            significant.removeLast()
            trailingZeros += 1
        }
        if significant.isEmpty {
            self = .decimal(isNegative: false, digits: [], exponent: SignedDigits(0))
        } else {
            self = .decimal(isNegative: isNegative, digits: significant, exponent: exponent.adding(trailingZeros - fraction.count))
        }
    }
}

/// A signed decimal integer of any length, for an exponent `Int` cannot hold.
private struct SignedDigits: Equatable {
    /// ASCII digits without leading zeros; empty for zero, which is never negative.
    private(set) var magnitude: [UInt8]
    private(set) var isNegative: Bool

    /// An optional sign followed by digits; empty text is zero.
    init(_ text: some Collection<UInt8>) {
        let digits = text.drop { $0 == UInt8(ascii: "-") || $0 == UInt8(ascii: "+") }
        magnitude = Array(digits.drop { $0 == UInt8(ascii: "0") })
        isNegative = text.first == UInt8(ascii: "-") && !magnitude.isEmpty
    }

    init(_ value: Int) {
        self.init(Array(String(value).utf8))
    }

    func adding(_ value: Int) -> SignedDigits {
        let other = SignedDigits(value)
        var result = self
        if isNegative == other.isNegative {
            result.magnitude = Self.sum(magnitude, other.magnitude)
        } else if Self.precedes(magnitude, other.magnitude) {
            result.magnitude = Self.difference(other.magnitude, magnitude)
            result.isNegative = other.isNegative
        } else {
            result.magnitude = Self.difference(magnitude, other.magnitude)
        }
        result.isNegative = result.isNegative && !result.magnitude.isEmpty
        return result
    }

    private static func precedes(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        lhs.count != rhs.count ? lhs.count < rhs.count : lhs.lexicographicallyPrecedes(rhs)
    }

    private static func sum(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
        var digits: [UInt8] = []
        var carry: UInt8 = 0
        var (left, right) = (lhs.reversed().makeIterator(), rhs.reversed().makeIterator())
        while true {
            let (a, b) = (left.next(), right.next())
            guard a != nil || b != nil || carry > 0 else {
                break
            }
            let total = (a.map { $0 - 48 } ?? 0) + (b.map { $0 - 48 } ?? 0) + carry
            digits.append(total % 10 + 48)
            carry = total / 10
        }
        return digits.reversed()
    }

    /// `lhs - rhs`, where `lhs` is not smaller.
    private static func difference(_ lhs: [UInt8], _ rhs: [UInt8]) -> [UInt8] {
        var digits: [UInt8] = []
        var borrow: Int8 = 0
        var right = rhs.reversed().makeIterator()
        for digit in lhs.reversed() {
            var value = Int8(digit - 48) - borrow - Int8(right.next().map { $0 - 48 } ?? 0)
            borrow = value < 0 ? 1 : 0
            if value < 0 {
                value += 10
            }
            digits.append(UInt8(value) + 48)
        }
        return Array(digits.reversed().drop { $0 == 48 })
    }
}
