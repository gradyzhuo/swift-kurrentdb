//
//  StreamMetadataTests.swift
//  swift-kurrentdb
//

import Foundation
import Testing
@testable import KurrentDB

@Suite("StreamMetadata Tests")
struct StreamMetadataTests {

    // MARK: - Default values

    @Test("Default StreamMetadata has all nil values and the server's default ACL")
    func testDefaultIsAllNil() throws {
        let metadata = StreamMetadata()
        #expect(metadata.maxCount == nil)
        #expect(metadata.maxAge == nil)
        #expect(metadata.truncateBefore == nil)
        #expect(metadata.cacheControl == nil)
        #expect(metadata.acl == .serverDefault)
        #expect(try object(of: metadata) == [:])
    }

    // MARK: - Builder methods

    @Test("maxCount builder sets value")
    func testMaxCount() {
        let metadata = StreamMetadata().maxCount(100)
        #expect(metadata.maxCount == 100)
    }

    @Test("maxAge builder sets value")
    func testMaxAge() {
        let metadata = StreamMetadata().maxAge(.seconds(3600))
        #expect(metadata.maxAge == .seconds(3600))
    }

    @Test("truncateBefore builder sets value")
    func testTruncateBefore() {
        let metadata = StreamMetadata().truncateBefore(42)
        #expect(metadata.truncateBefore == 42)
    }

    @Test("cacheControl builder sets value")
    func testCacheControl() {
        let metadata = StreamMetadata().cacheControl(.seconds(10))
        #expect(metadata.cacheControl == .seconds(10))
    }

    @Test("acl builder writes the stream's roles as the $acl object")
    func testAclStream() throws {
        let roles = StreamMetadata.StreamAcl.defaults.readRoles(["$all"]).metaWriteRoles(["ops"])
        let metadata = StreamMetadata().acl(.stream(roles))
        #expect(metadata.acl == .stream(roles))
        #expect(String(decoding: metadata.data, as: UTF8.self) == #"{"$acl":{"$mw":["ops"],"$r":["$all"]}}"#)
    }

    @Test("acl(.serverDefault) removes $acl and leaves every other key")
    func testAclServerDefault() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$acl":{"$r":"ops"},"$maxCount":5,"tenant":"acme"}"#.utf8))
            .acl(.serverDefault)
        #expect(metadata.acl == .serverDefault)
        #expect(String(decoding: metadata.data, as: UTF8.self) == #"{"$maxCount":5,"tenant":"acme"}"#)
        #expect(StreamMetadata().acl(.serverDefault).data == Data("{}".utf8))
    }

    @available(*, deprecated)
    @Test("The deprecated customProperties(_:) writes top-level string keys and skips $ keys")
    func testCustomProperties() throws {
        let props = ["env": "test", "owner": "team-a"]
        let metadata = StreamMetadata().customProperties(props)
        #expect(try object(of: metadata) == ["env": .string("test"), "owner": .string("team-a")])
        #expect(try object(of: StreamMetadata().customProperties(["$maxCount": "1", "env": "test"])) == ["env": .string("test")])
    }

    // MARK: - Immutability

    @Test("Builder methods do not mutate the original")
    func testBuilderIsImmutable() {
        let original = StreamMetadata()
        let modified = original.maxCount(50)
        #expect(original.maxCount == nil)
        #expect(modified.maxCount == 50)
    }

    @Test("Chained builder preserves all values")
    func testChainedBuilderPreservesAll() {
        let metadata = StreamMetadata()
            .maxCount(200)
            .maxAge(.seconds(86400))
            .cacheControl(.seconds(5))
            .acl(.stream(StreamMetadata.StreamAcl.defaults.readRoles(["$all"])))
        #expect(metadata.maxCount == 200)
        #expect(metadata.maxAge == .seconds(86400))
        #expect(metadata.cacheControl == .seconds(5))
        #expect(metadata.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["$all"])))
    }

    // MARK: - Codable

    @Test("JSON roundtrip preserves all set values")
    func testJSONRoundtrip() throws {
        let original = StreamMetadata()
            .maxCount(10)
            .maxAge(.seconds(300))
            .acl(.stream(StreamMetadata.StreamAcl.defaults.readRoles(["$all"])))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StreamMetadata.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Acl and StreamAcl.Roles

    @Test("Acl is not Codable: the server ignores the whole metadata for \"$acl\":null")
    func testAclIsNotCodable() {
        let acl: Any = StreamMetadata.Acl.serverDefault
        #expect(!(acl is any Encodable))
        #expect(!(acl is any Decodable))
    }

    @Test("StreamAcl.defaults stores the empty object, and every getter reads .defaults")
    func testStreamAclDefaults() throws {
        let acl = StreamMetadata.StreamAcl.defaults
        #expect(try JSONEncoder().encode(acl) == Data("{}".utf8))
        #expect(acl.readRoles == .defaults)
        #expect(acl.writeRoles == .defaults)
        #expect(acl.deleteRoles == .defaults)
        #expect(acl.metaReadRoles == .defaults)
        #expect(acl.metaWriteRoles == .defaults)
        #expect(String(decoding: StreamMetadata().acl(.stream(.defaults)).data, as: UTF8.self) == #"{"$acl":{}}"#)
    }

    @Test("Decoding a StreamAcl on its own throws for a null role, which the server ignores the metadata for")
    func testStreamAclNullRoleThrows() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StreamMetadata.StreamAcl.self, from: Data(#"{"$r":null}"#.utf8))
        }
    }

    @Test("Metadata holding \"$acl\":{} reads as .stream(.defaults), not .serverDefault")
    func testEmptyAclObjectIsNotServerDefault() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$acl":{}}"#.utf8))
        #expect(metadata.acl == .stream(.defaults))
        #expect(metadata.acl != .serverDefault)
    }

    @Test("An array literal is Roles.granted")
    func testRolesArrayLiteral() {
        let roles: StreamMetadata.StreamAcl.Roles = ["ops", "dev"]
        #expect(roles == .granted(["ops", "dev"]))
        #expect(StreamMetadata.StreamAcl.defaults.writeRoles(["ops"]).writeRoles == .granted(["ops"]))
        let names = ["a", "b"]
        #expect(StreamMetadata.StreamAcl.defaults.readRoles(.granted(names)).readRoles == ["a", "b"])
    }

    @Test(".defaults removes a permission from a decoded ACL and keeps the others")
    func testRolesDefaultsRemovesKey() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$acl":{"$r":["a"],"$w":"b","$mw":[]}}"#.utf8))
        guard case let .stream(acl) = metadata.acl else {
            Issue.record("Expected a stream ACL, got \(String(describing: metadata.acl)).")
            return
        }
        let updated = metadata.acl(.stream(acl.writeRoles(.defaults)))
        #expect(String(decoding: updated.data, as: UTF8.self) == #"{"$acl":{"$mw":[],"$r":["a"]}}"#)
    }

    @Test("Getters read .defaults for an absent permission and .granted([]) for an empty list")
    func testRolesGetters() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$acl":{"$mw":[]}}"#.utf8))
        guard case let .stream(acl) = metadata.acl else {
            Issue.record("Expected a stream ACL, got \(String(describing: metadata.acl)).")
            return
        }
        #expect(acl.metaWriteRoles == .granted([]))
        #expect(acl.readRoles == .defaults)
        #expect(acl != .defaults)
        #expect(acl == StreamMetadata.StreamAcl.defaults.metaWriteRoles([]))
    }

    // MARK: - StreamAcl builder

    @Test("StreamAcl readRoles builder sets value")
    func testStreamAclReadRoles() {
        let acl = StreamMetadata.StreamAcl.defaults.readRoles(["admin", "reader"])
        #expect(acl.readRoles == ["admin", "reader"])
    }

    @Test("StreamAcl writeRoles builder sets value")
    func testStreamAclWriteRoles() {
        let acl = StreamMetadata.StreamAcl.defaults.writeRoles(["admin"])
        #expect(acl.writeRoles == ["admin"])
    }

    @Test("StreamAcl deleteRoles builder sets value")
    func testStreamAclDeleteRoles() {
        let acl = StreamMetadata.StreamAcl.defaults.deleteRoles(["admin"])
        #expect(acl.deleteRoles == ["admin"])
    }

    @Test("StreamAcl metaReadRoles builder sets value")
    func testStreamAclMetaReadRoles() {
        let acl = StreamMetadata.StreamAcl.defaults.metaReadRoles(["admin"])
        #expect(acl.metaReadRoles == ["admin"])
    }

    @Test("StreamAcl metaWriteRoles builder sets value")
    func testStreamAclMetaWriteRoles() {
        let acl = StreamMetadata.StreamAcl.defaults.metaWriteRoles(["admin"])
        #expect(acl.metaWriteRoles == ["admin"])
    }

    @Test("StreamAcl builder is immutable")
    func testStreamAclBuilderImmutability() {
        let original = StreamMetadata.StreamAcl.defaults
        let modified = original.readRoles(["admin"])
        #expect(original.readRoles == .defaults)
        #expect(modified.readRoles == ["admin"])
    }

    // MARK: - The stored JSON object

    /// Metadata as another client writes it: system fields and custom keys side by side at the top level.
    static let otherClientJSON = #"""
    {"$maxCount":10,"$maxAge":60,"$tb":5,"$cacheControl":10,"$acl":{"$r":["a"],"$w":["b"]},"tenant":"acme","retries":3}
    """#

    private func object(of metadata: StreamMetadata) throws -> [String: PropertyValue] {
        try JSONDecoder().decode([String: PropertyValue].self, from: metadata.data)
    }

    private func object(of json: String) throws -> [String: PropertyValue] {
        try JSONDecoder().decode([String: PropertyValue].self, from: Data(json.utf8))
    }

    @Test("Every getter reads metadata written by another client")
    func testReadsOtherClientMetadata() throws {
        let metadata = try StreamMetadata(data: Data(Self.otherClientJSON.utf8))
        #expect(metadata.maxCount == 10)
        #expect(metadata.maxAge == .seconds(60))
        #expect(metadata.truncateBefore == 5)
        #expect(metadata.cacheControl == .seconds(10))
        #expect(metadata.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["a"]).writeRoles(["b"])))
        #expect(metadata.data == Data(Self.otherClientJSON.utf8))
    }

    @Test("A role written as a single string reads as a one-element list")
    func testAclSingleRoleString() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$acl":{"$r":"admin","$w":["ops","dev"]}}"#.utf8))
        guard case let .stream(acl) = metadata.acl else {
            Issue.record("Expected a stream ACL, got \(String(describing: metadata.acl)).")
            return
        }
        #expect(acl.readRoles == ["admin"])
        #expect(acl.writeRoles == ["ops", "dev"])
        #expect(acl.deleteRoles == .defaults)
    }

    @Test("$maxCount and $tb read up to Int64.max, the soft-delete $tb")
    func testLargeIntegers() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$maxCount":9223372036854775807,"$tb":9223372036854775807}"#.utf8))
        #expect(metadata.maxCount == UInt64(Int64.max))
        #expect(metadata.truncateBefore == UInt64(Int64.max))
    }

    @Test("The builders take their largest allowed values")
    func testBuilderLimits() throws {
        let metadata = StreamMetadata()
            .maxCount(UInt64(Int64.max))
            .truncateBefore(UInt64(Int64.max))
            .maxAge(.seconds(62_000_000_000))
            .cacheControl(.seconds(922_337_203_685))
        #expect(metadata.maxCount == UInt64(Int64.max))
        #expect(metadata.truncateBefore == UInt64(Int64.max))
        #expect(metadata.maxAge == .seconds(62_000_000_000))
        #expect(metadata.cacheControl == .seconds(922_337_203_685))
        #expect(try object(of: metadata) == [
            "$maxCount": .integer(Int64.max),
            "$tb": .integer(Int64.max),
            "$maxAge": .integer(62_000_000_000),
            "$cacheControl": .integer(922_337_203_685),
        ])
        #expect(StreamMetadata().maxCount(0).maxCount == 0)
    }

    // MARK: - Strict reading

    @Test("init(data:) throws for metadata the server ignores as a whole", arguments: [
        // Numbers the server reads as floats, or that do not fit in a long.
        #"{"$maxCount":2.0}"#,
        #"{"$maxCount":2e0}"#,
        #"{"$maxAge":60.0}"#,
        #"{"$maxAge":1.5}"#,
        #"{"$cacheControl":1E3}"#,
        #"{"$maxCount":9223372036854775808}"#,
        #"{"$maxCount":18446744073709551615}"#,
        #"{"$tb":-9223372036854775809}"#,
        // Durations outside .NET's TimeSpan.
        #"{"$maxAge":922337203686}"#,
        #"{"$maxAge":-922337203686}"#,
        #"{"$cacheControl":922337203686}"#,
        #"{"$cacheControl":9223372036854775807}"#,
        // Other tokens, including a 2.x client's Duration.
        #"{"$maxCount":"10"}"#,
        #"{"$tb":null}"#,
        #"{"$tb":true}"#,
        #"{"$maxAge":[3,4659767778871345152]}"#,
        #"{"$cacheControl":[-1,17446744073709551616]}"#,
        // $tmp is a boolean.
        #"{"$tmp":"true"}"#,
        #"{"$tmp":1}"#,
        #"{"$tmp":null}"#,
        // $acl is an object of role lists.
        #"{"$acl":"$userStreamAcl"}"#,
        #"{"$acl":"$systemStreamAcl"}"#,
        #"{"$acl":null}"#,
        #"{"$acl":42}"#,
        #"{"$acl":{"$x":"a"}}"#,
        #"{"$acl":{"other":{"a":1}}}"#,
        #"{"$acl":{"$r":null}}"#,
        #"{"$acl":{"$r":[null]}}"#,
        #"{"$acl":{"$r":[1]}}"#,
        #"{"$acl":{"$r":1}}"#,
        // Every occurrence of a repeated key is checked, as the server checks them in turn.
        #"{"$maxCount":"x","$maxCount":2}"#,
        #"{"$maxCount":2,"$maxCount":"x"}"#,
        #"{"$acl":{"$r":1,"$r":["b"]}}"#,
        #"{"$acl":"x","$acl":{"$r":"$all"}}"#,
        #"{"$acl":{"$r":"$all"},"$acl":"x"}"#,
        // A system key written with an escape.
        #"{"$maxCount":1.5}"#,
    ])
    func testStrictReadingThrows(json: String) {
        #expect {
            try StreamMetadata(data: Data(json.utf8))
        } throws: { error in
            guard case .internalParsingError = error as? KurrentError else { return false }
            return true
        }
    }

    @Test("Decoding checks the values the decoder hands over, the first occurrence of a repeated key for JSONDecoder", arguments: [
        #"{"$maxCount":"10"}"#,
        #"{"$maxAge":1.5}"#,
        #"{"$maxCount":9223372036854775808}"#,
        #"{"$maxAge":[3,4659767778871345152]}"#,
        #"{"$tmp":1}"#,
        #"{"$acl":"$userStreamAcl"}"#,
        #"{"$acl":{"$x":"a"}}"#,
        #"{"$acl":{"$r":[1]}}"#,
        #"{"$maxCount":"x","$maxCount":2}"#,
    ])
    func testDecodingChecksSystemKeys(json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StreamMetadata.self, from: Data(json.utf8))
        }
    }

    @Test("The error names the key and the value")
    func testStrictReadingReason() {
        #expect {
            try StreamMetadata(data: Data(#"{"$maxCount":2,"$maxAge":[3,4659767778871345152]}"#.utf8))
        } throws: { error in
            guard case let .internalParsingError(reason) = error as? KurrentError else { return false }
            return reason.contains("$maxAge") && reason.contains("[3,4659767778871345152]")
        }
    }

    @Test("init(data:) reads what the server reads, including the values it ignores", arguments: [
        #"{"$maxCount":-1,"$tb":-9223372036854775808,"$maxAge":0,"$cacheControl":-5}"#,
        #"{"$maxAge":922337203685,"$cacheControl":-922337203685}"#,
        #"{"$maxAge":62000000001}"#,
        #"{"$maxCount":-0}"#,
        #"{"$tmp":true}"#,
        #"{"$tmp":false}"#,
        #"{"$acl":{}}"#,
        #"{"$acl":{"$r":[],"$w":"a","$d":["a","b"],"$mr":"$all","$mw":["$admins"]}}"#,
        #"{"$acl":{"$r":"a"}}"#,
        // Keys the server skips, whatever they hold; key comparison is case-sensitive.
        #"{"$future":"x","custom":[1,2.5,{"a":null}],"$x":{"y":[true]},"$MaxCount":"x","maxCount":1.5}"#,
    ])
    func testStrictReadingAccepts(json: String) throws {
        #expect(try StreamMetadata(data: Data(json.utf8)).data == Data(json.utf8))
        _ = try JSONDecoder().decode(StreamMetadata.self, from: Data(json.utf8))
    }

    @Test("Negative and zero values read as stored; the server ignores those fields")
    func testIgnoredValues() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$maxCount":-1,"$tb":-5,"$maxAge":0,"$cacheControl":-5}"#.utf8))
        #expect(metadata.maxCount == nil)
        #expect(metadata.truncateBefore == nil)
        #expect(metadata.maxAge == .seconds(0))
        #expect(metadata.cacheControl == .seconds(-5))
        let limits = try StreamMetadata(data: Data(#"{"$maxAge":922337203685,"$cacheControl":-922337203685}"#.utf8))
        #expect(limits.maxAge == .seconds(922_337_203_685))
        #expect(limits.cacheControl == .seconds(-922_337_203_685))
    }

    private static let maxCountTwo = #"{"$maxCount":2}"#

    private static func utf16(_ text: String, bigEndian: Bool) -> Data {
        Data(text.utf16.flatMap { (unit: UInt16) -> [UInt8] in
            let bytes = [UInt8(unit & 0xFF), UInt8(unit >> 8)]
            return bigEndian ? bytes.reversed() : bytes
        })
    }

    private static func utf32(_ text: String, bigEndian: Bool) -> Data {
        Data(text.unicodeScalars.flatMap { (scalar: Unicode.Scalar) -> [UInt8] in
            let bytes = [UInt8(scalar.value & 0xFF), 0, 0, 0]
            return bigEndian ? bytes.reversed() : bytes
        })
    }

    @Test("init(data:) throws for UTF-16 and UTF-32, with or without a byte order mark", arguments: [
        Data([0xFF, 0xFE]) + utf16(maxCountTwo, bigEndian: false),
        Data([0xFE, 0xFF]) + utf16(maxCountTwo, bigEndian: true),
        utf16(maxCountTwo, bigEndian: false),
        Data([0xFF, 0xFE, 0, 0]) + utf32(maxCountTwo, bigEndian: false),
        utf32(maxCountTwo, bigEndian: true),
    ])
    func testNonUTF8Throws(data: Data) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: data)
        }
    }

    @Test("A trailing comma is accepted, as JSONDecoder and the server accept it")
    func testTrailingCommas() throws {
        let repeated = try StreamMetadata(data: Data(#"{"$maxCount":100,"$maxCount":2,}"#.utf8))
        #expect(repeated.maxCount == 2)
        #expect(String(decoding: repeated.data, as: UTF8.self) == #"{"$maxCount":2}"#)
        let json = #"{ "$acl" : { "$r" : [ "a" , ] , } , "k" : [ 1 , ] , }"#
        let kept = try StreamMetadata(data: Data(json.utf8))
        #expect(kept.data == Data(json.utf8))
        #expect(kept.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["a"])))
        let nested = try StreamMetadata(data: Data(#"{"o":{"k":1,"k":2,},"a":[{"y":1,"y":3,},],}"#.utf8))
        #expect(String(decoding: nested.data, as: UTF8.self) == #"{"o":{"k":2},"a":[{"y":3}]}"#)
    }

    @Test("Keys are compared by Unicode scalars: canonically equivalent keys are two keys")
    func testCanonicallyEquivalentKeys() throws {
        let json = "{\"caf\u{E9}\":1,\"cafe\u{301}\":2}"
        #expect(try #require(JSONText(Data(json.utf8))).keepingLastOccurrences == nil)
        #expect(try StreamMetadata(data: Data(json.utf8)).data == Data(json.utf8))
        // An escape denotes the same scalars as the character it stands for.
        let escaped = "{\"caf\\u00e9\":1,\"cafe\u{301}\":2,\"caf\u{E9}\":3}"
        #expect(try StreamMetadata(data: Data(escaped.utf8)).data == Data("{\"cafe\u{301}\":2,\"caf\u{E9}\":3}".utf8))
    }

    @Test("A builder keeps every other member's bytes and place, and appends a new key")
    func testBuilderKeepsOtherMembers() throws {
        let metadata = try StreamMetadata(data: Data(#"{"z":1,"$tb":3,"a":{"y":true, "b":null}}"#.utf8))
            .maxCount(2)
            .acl(.stream(StreamMetadata.StreamAcl.defaults.writeRoles(["w"]).readRoles(["r"])))
            .cacheControl(.seconds(5))
            .truncateBefore(4)
        #expect(String(decoding: metadata.data, as: UTF8.self) == #"{"z":1,"$tb":4,"a":{"y":true, "b":null},"$maxCount":2,"$acl":{"$r":["r"],"$w":["w"]},"$cacheControl":5}"#)
    }

    @Test("A builder keeps keys that differ only in Unicode normalization apart")
    func testBuilderKeepsCanonicallyEquivalentKeys() throws {
        let json = "{\"caf\u{E9}\":1,\"cafe\u{301}\":2,\"$acl\":{\"$r\":\"ops\"}}"
        let metadata = try StreamMetadata(data: Data(json.utf8))
        #expect(metadata.maxCount(2).data == Data("{\"caf\u{E9}\":1,\"cafe\u{301}\":2,\"$acl\":{\"$r\":\"ops\"},\"$maxCount\":2}".utf8))
        #expect(metadata.acl(.serverDefault).data == Data("{\"caf\u{E9}\":1,\"cafe\u{301}\":2}".utf8))
        #expect(try metadata.customProperty("caf\u{E9}", as: Int.self) == 1)
        #expect(try metadata.customProperty("cafe\u{301}", as: Int.self) == 2)
        #expect(try metadata.customProperty("cafe\u{301}", encoding: 3).data == Data("{\"caf\u{E9}\":1,\"cafe\u{301}\":3,\"$acl\":{\"$r\":\"ops\"}}".utf8))
    }

    @Test("A builder keeps every digit of a number it does not set")
    func testBuilderKeepsNumbers() throws {
        let json = #"{"ratio":1.234567890123456789,"big":123456789012345678901234567890,"e":6e1}"#
        let metadata = try StreamMetadata(data: Data(json.utf8))
            .maxAge(.seconds(60))
            .customProperty("tenant", encoding: "acme")
        #expect(String(decoding: metadata.data, as: UTF8.self) == #"{"ratio":1.234567890123456789,"big":123456789012345678901234567890,"e":6e1,"$maxAge":60,"tenant":"acme"}"#)
        #expect(try metadata.customProperty("ratio", as: Decimal.self) == Decimal(string: "1.234567890123456789"))
    }

    // MARK: - Nesting depth

    /// A metadata object whose `k` member nests arrays, so the text is `depth` levels deep.
    private static func nested(depth: Int) -> String {
        #"{"k":"# + String(repeating: "[", count: depth - 1) + String(repeating: "]", count: depth - 1) + "}"
    }

    @Test("Metadata nested 64 levels deep is read and written back")
    func testNestedAtTheLimit() throws {
        let metadata = try StreamMetadata(data: Data(Self.nested(depth: 64).utf8))
        #expect(try object(of: metadata.maxCount(1))["$maxCount"] == .integer(1))
        let decoded = try JSONDecoder().decode(StreamMetadata.self, from: Data(Self.nested(depth: 64).utf8))
        #expect(decoded == metadata)
    }

    @Test("Metadata nested deeper than 64 levels throws instead of overflowing the stack", arguments: [65, 1_000, 100_000])
    func testNestedPastTheLimit(depth: Int) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: Data(Self.nested(depth: depth).utf8))
        }
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StreamMetadata.self, from: Data(Self.nested(depth: depth).utf8))
        }
    }

    // MARK: - Repeated keys

    @Test("A repeated top-level key reads as its last occurrence, as the server reads it, and a builder keeps it")
    func testRepeatedTopLevelKey() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$maxCount":2,"$maxCount":100}"#.utf8))
        #expect(metadata.maxCount == 100)
        #expect(String(decoding: metadata.data, as: UTF8.self) == #"{"$maxCount":100}"#)
        let rewritten = metadata.cacheControl(.seconds(5))
        #expect(rewritten.maxCount == 100)
        #expect(String(decoding: rewritten.data, as: UTF8.self) == #"{"$maxCount":100,"$cacheControl":5}"#)
    }

    @Test("A repeated key after a UTF-8 byte order mark reads as its last occurrence")
    func testRepeatedKeyAfterByteOrderMark() throws {
        let metadata = try StreamMetadata(data: Data([0xEF, 0xBB, 0xBF]) + Data(#"{"$maxCount":1,"$maxCount":7}"#.utf8))
        #expect(metadata.maxCount == 7)
    }

    @Test("Repeated keys read as their last occurrence", arguments: [
        // Inside $acl.
        (#"{"$acl":{"$r":"a","$w":"w","$r":["b"]}}"#, #"{"$acl":{"$w":"w","$r":["b"]}}"#),
        // Inside nested custom objects and arrays, with whitespace.
        (#"{ "o" : { "k" : 1 , "k" : { "x" : 1 , "x" : 2 } } , "a" : [ { "y" : 1 , "y" : 3 } , 4 ] }"#, #"{"o":{"k":{"x":2}},"a":[{"y":3},4]}"#),
        // The same key written with an escape.
        (#"{"\u0024maxCount":1,"$maxCount":7}"#, #"{"$maxCount":7}"#),
        // A key holding an escaped quote.
        (#"{"a\"b":1,"c":2,"a\"b":3}"#, #"{"c":2,"a\"b":3}"#),
        // Strings holding braces, brackets, commas, colons and quoted keys.
        (#"{"s":"{\"$maxCount\":1}","$maxCount":3,"t":"}],:\\","$maxCount":4}"#, #"{"s":"{\"$maxCount\":1}","t":"}],:\\","$maxCount":4}"#),
    ])
    func testRepeatedNestedKeys(json: String, expected: String) throws {
        let metadata = try StreamMetadata(data: Data(json.utf8))
        #expect(String(decoding: metadata.data, as: UTF8.self) == expected)
        #expect(try object(of: metadata) == object(of: expected))
    }

    @Test("Metadata without a repeated key is kept byte for byte", arguments: [
        #"{ "s" : "{\"k\":1,\"k\":2}" , "o" : { "k" : [ { "k" : 1 } ] } , "k" : -1.5e3 , "n" : null , "e" : { } , "l" : [ ] }"#,
        Self.otherClientJSON,
    ])
    func testWithoutRepeatedKeys(json: String) throws {
        #expect(try #require(JSONText(Data(json.utf8))).keepingLastOccurrences == nil)
        #expect(try StreamMetadata(data: Data(json.utf8)).data == Data(json.utf8))
    }

    @Test("A repeated $acl role reaches the ACL as its last occurrence")
    func testRepeatedAclRole() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$acl":{"$r":"a","$r":["b","c"]}}"#.utf8))
        #expect(metadata.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["b", "c"])))
    }

    @Test("A builder keeps unknown $ keys and custom keys")
    func testBuilderKeepsUnknownKeys() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$future":{"x":[1,true]},"tenant":"acme","$maxCount":5}"#.utf8))
            .maxCount(1)
        #expect(try object(of: metadata) == object(of: #"{"$future":{"x":[1,true]},"tenant":"acme","$maxCount":1}"#))
    }

    @Test("maxAge and cacheControl are written in whole seconds, sub-second parts truncated")
    func testDurationsInWholeSeconds() throws {
        #expect(try object(of: StreamMetadata().maxAge(.seconds(60))) == ["$maxAge": .integer(60)])
        #expect(try object(of: StreamMetadata().maxAge(.milliseconds(1500))) == ["$maxAge": .integer(1)])
        #expect(try object(of: StreamMetadata().cacheControl(.seconds(10))) == ["$cacheControl": .integer(10)])
        #expect(try object(of: StreamMetadata().cacheControl(.milliseconds(2999))) == ["$cacheControl": .integer(2)])
    }

    @Test("maxAge and cacheControl under one second are written as they are")
    func durationUnderOneSecondIsKept() throws {
        #expect(try object(of: StreamMetadata().maxAge(.milliseconds(500))) == ["$maxAge": .integer(0)])
        #expect(try object(of: StreamMetadata().maxAge(.seconds(-5))) == ["$maxAge": .integer(-5)])
        #expect(try object(of: StreamMetadata().cacheControl(.milliseconds(-500))) == ["$cacheControl": .integer(0)])
        #expect(StreamMetadata().maxAge(.seconds(-5)).maxAge == .seconds(-5))
    }

    @Test("init(data:) throws unless the JSON is an object", arguments: [
        "[1,2]",
        #""metadata""#,
        "42",
        "not json",
    ])
    func testInitRejectsNonObject(json: String) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: Data(json.utf8))
        }
    }

    @Test("Decoding a non-object throws DecodingError")
    func testDecodingRejectsNonObject() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(StreamMetadata.self, from: Data("[1,2]".utf8))
        }
    }

    @Test("== compares every field, including maxCount")
    func testEqualityIncludesMaxCount() {
        #expect(StreamMetadata().maxCount(1) != StreamMetadata().maxCount(2))
    }

    @Test("== ignores key order and number spelling")
    func testEqualityIgnoresKeyOrder() throws {
        let lhs = try StreamMetadata(data: Data(#"{"$maxCount":10,"tenant":"acme","$maxAge":60,"n":10}"#.utf8))
        let rhs = try StreamMetadata(data: Data(#"{"$maxAge":60,"tenant":"acme","$maxCount":10,"n":1e1}"#.utf8))
        #expect(lhs == rhs)
        #expect(try lhs != rhs.customProperty("tenant", encoding: "other"))
    }

    @Test("A Codable round trip keeps the JSON object")
    func testCodableRoundTripKeepsObject() throws {
        let original = try StreamMetadata(data: Data(Self.otherClientJSON.utf8))
        let encoded = try JSONEncoder().encode(original)
        #expect(try object(of: String(decoding: encoded, as: UTF8.self)) == object(of: Self.otherClientJSON))
        let decoded = try JSONDecoder().decode(StreamMetadata.self, from: encoded)
        #expect(decoded == original)
        #expect(try object(of: decoded) == object(of: Self.otherClientJSON))
    }

    @Test("customProperties(encoding:) merges top-level keys")
    func testCustomPropertiesMerge() throws {
        let metadata = try StreamMetadata(data: Data(#"{"tenant":"acme","retries":3}"#.utf8))
            .customProperties(encoding: ["tenant": "other", "env": "test"])
        #expect(try object(of: metadata) == object(of: #"{"tenant":"other","retries":3,"env":"test"}"#))
    }

    // MARK: - Custom properties of any JSON value

    private struct Settings: Codable, Equatable {
        struct Owner: Codable, Equatable {
            var team: String
            var oncall: [String]
        }

        var tenant: String
        var retries: Int
        var archived: Bool
        var ratio: Double
        var owner: Owner
    }

    private static let settings = Settings(
        tenant: "acme", retries: 3, archived: false, ratio: 0.25,
        owner: .init(team: "orders", oncall: ["ann", "bob"])
    )

    @Test("Nested objects, numbers and booleans round trip through customProperties(encoding:) and (as:)")
    func testCustomPropertiesRoundTrip() throws {
        let metadata = try StreamMetadata().maxCount(10).customProperties(encoding: Self.settings)
        #expect(try object(of: metadata) == object(of: #"{"$maxCount":10,"tenant":"acme","retries":3,"archived":false,"ratio":0.25,"owner":{"team":"orders","oncall":["ann","bob"]}}"#))
        #expect(try metadata.customProperties(as: Settings.self) == Self.settings)
        #expect(metadata.maxCount == 10)

        let reread = try StreamMetadata(data: metadata.data)
        #expect(try reread.customProperty("retries", as: Int.self) == 3)
        #expect(try reread.customProperty("archived", as: Bool.self) == false)
        #expect(try reread.customProperty("owner", as: Settings.Owner.self) == Self.settings.owner)
    }

    @Test("customProperties(as:) decodes only the keys not starting with $")
    func testCustomPropertiesAsSkipsReservedKeys() throws {
        let metadata = try StreamMetadata(data: Data(Self.otherClientJSON.utf8))
        let custom = try metadata.customProperties(as: [String: PropertyValue].self)
        #expect(custom == ["tenant": .string("acme"), "retries": .integer(3)])
    }

    @Test("customProperty(_:encoding:) stores any JSON value under one key, leaving the others")
    func testCustomPropertyEncoding() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$maxCount":5,"tenant":"acme"}"#.utf8))
            .customProperty("limits", encoding: [1, 2, 3])
            .customProperty("enabled", encoding: true)
            .customProperty("note", encoding: String?.none)
        #expect(try object(of: metadata) == object(of: #"{"$maxCount":5,"tenant":"acme","limits":[1,2,3],"enabled":true,"note":null}"#))
        #expect(try metadata.customProperty("limits", as: [Int].self) == [1, 2, 3])
    }

    @Test("customProperty(_:as:) returns nil for an absent key and for a $ key")
    func testCustomPropertyAbsent() throws {
        let metadata = try StreamMetadata(data: Data(Self.otherClientJSON.utf8))
        #expect(try metadata.customProperty("missing", as: String.self) == nil)
        #expect(try metadata.customProperty("$maxCount", as: Int.self) == nil)
    }

    @Test("A custom value of the wrong type throws internalParsingError")
    func testCustomPropertyWrongType() throws {
        let metadata = try StreamMetadata(data: Data(Self.otherClientJSON.utf8))
        #expect {
            try metadata.customProperty("tenant", as: Int.self)
        } throws: { error in
            guard case .internalParsingError = error as? KurrentError else { return false }
            return true
        }
        #expect(throws: KurrentError.self) {
            try metadata.customProperties(as: Settings.self)
        }
    }

    @Test("A $ key throws encodingError")
    func testReservedKeyThrows() {
        #expect {
            try StreamMetadata().customProperty("$maxCount", encoding: 1)
        } throws: { error in
            guard case .encodingError = error as? KurrentError else { return false }
            return true
        }
        #expect {
            try StreamMetadata().customProperties(encoding: ["tenant": "acme", "$tb": "1"])
        } throws: { error in
            guard case .encodingError = error as? KurrentError else { return false }
            return true
        }
    }

    @Test("customProperties(encoding:) throws unless the value encodes to a JSON object", arguments: [
        #"["a","b"]"#,
        #""acme""#,
        "42",
        "null",
    ])
    func testNonObjectEncodingThrows(json: String) throws {
        let value = try JSONDecoder().decode(PropertyValue.self, from: Data(json.utf8))
        #expect(throws: KurrentError.self) {
            try StreamMetadata().customProperties(encoding: value)
        }
    }

    @Test("customProperties(encoding:) throws for public non-object values")
    func testPublicNonObjectEncodingThrows() {
        #expect(throws: KurrentError.self) {
            try StreamMetadata().customProperties(encoding: [1, 2])
        }
        #expect(throws: KurrentError.self) {
            try StreamMetadata().customProperties(encoding: String?.none)
        }
    }

    @Test("A custom integer above 2^53 round trips exactly")
    func testLargeCustomInteger() throws {
        let metadata = try StreamMetadata()
            .customProperty("big", encoding: UInt64.max)
            .customProperty("signed", encoding: Int64.min)
        #expect(try metadata.customProperty("big", as: UInt64.self) == UInt64.max)
        #expect(try metadata.customProperty("signed", as: Int64.self) == Int64.min)
    }

    @Test("customProperty(_:encoding:) throws for a value JSONEncoder rejects")
    func testNonFiniteNumberThrows() {
        #expect(throws: KurrentError.self) {
            try StreamMetadata().customProperty("ratio", encoding: Double.nan)
        }
        #expect(throws: KurrentError.self) {
            try StreamMetadata().customProperty("ratio", encoding: Double.infinity)
        }
    }

    // MARK: - Nesting depth of custom values

    /// `depth` arrays around a scalar.
    private static func nestedArray(depth: Int) -> PropertyValue {
        (0 ..< depth).reduce(PropertyValue.integer(1)) { value, _ in .array([value]) }
    }

    @Test("A custom value that keeps the stored object within 64 levels is written and read back")
    func testCustomValueAtTheDepthLimit() throws {
        let single = try StreamMetadata().customProperty("k", encoding: Self.nestedArray(depth: 63))
        #expect(try StreamMetadata(data: single.data).customProperty("k", as: PropertyValue.self) == Self.nestedArray(depth: 63))
        let merged = try StreamMetadata().customProperties(encoding: PropertyValue.object(["k": Self.nestedArray(depth: 63)]))
        #expect(try StreamMetadata(data: merged.data) == single)
    }

    @Test("A custom value that would make the stored object nest more than 64 levels throws encodingError", arguments: [64, 65, 100])
    func testCustomValuePastTheDepthLimit(depth: Int) {
        #expect {
            try StreamMetadata().customProperty("k", encoding: Self.nestedArray(depth: depth))
        } throws: { error in
            guard case .encodingError = error as? KurrentError else { return false }
            return true
        }
        #expect {
            try StreamMetadata().customProperties(encoding: PropertyValue.object(["k": Self.nestedArray(depth: depth)]))
        } throws: { error in
            guard case .encodingError = error as? KurrentError else { return false }
            return true
        }
    }
}
