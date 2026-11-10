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
        #expect(try json(metadata) == #"{"$acl":{"$r":["$all"],"$mw":["ops"]}}"#)
    }

    @Test("acl(.serverDefault) removes $acl and leaves every other key")
    func testAclServerDefault() throws {
        let metadata = try read(#"{"$acl":{"$r":"ops"},"$maxCount":5,"tenant":"acme"}"#).acl(.serverDefault)
        #expect(metadata.acl == .serverDefault)
        #expect(try json(metadata) == #"{"$maxCount":5,"tenant":"acme"}"#)
        #expect(try json(StreamMetadata().acl(.serverDefault)) == "{}")
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

    // MARK: - Writing and reading back

    @Test("What is written reads back equal")
    func testRoundTrip() throws {
        let original = try StreamMetadata()
            .maxCount(10)
            .maxAge(.seconds(300))
            .acl(.stream(StreamMetadata.StreamAcl.defaults.readRoles(["$all"])))
            .customProperty("tenant", encoding: "acme")
        #expect(try StreamMetadata(data: original.encoded()) == original)
    }

    @Test("String(reflecting:) is the JSON setMetadata sends")
    func testDebugDescription() {
        #expect(String(reflecting: StreamMetadata().maxCount(1)) == #"{"$maxCount":1}"#)
        #expect(String(reflecting: StreamMetadata()) == "{}")
    }

    // MARK: - Acl and StreamAcl.Roles

    @Test("StreamMetadata, StreamAcl and Acl are not Codable: JSONDecoder and JSONEncoder do not read and write as the server does")
    func testNotCodable() {
        let values: [Any] = [StreamMetadata(), StreamMetadata.StreamAcl.defaults, StreamMetadata.Acl.serverDefault]
        for value in values {
            #expect(!(value is any Encodable))
            #expect(!(value is any Decodable))
        }
    }

    @Test("StreamAcl.defaults stores the empty object, and every getter reads .defaults")
    func testStreamAclDefaults() throws {
        let acl = StreamMetadata.StreamAcl.defaults
        #expect(acl.readRoles == .defaults)
        #expect(acl.writeRoles == .defaults)
        #expect(acl.deleteRoles == .defaults)
        #expect(acl.metaReadRoles == .defaults)
        #expect(acl.metaWriteRoles == .defaults)
        #expect(try json(StreamMetadata().acl(.stream(.defaults))) == #"{"$acl":{}}"#)
    }

    @Test("Decoding a StreamAcl on its own throws for a null role, which the server ignores the metadata for")
    func testStreamAclNullRoleThrows() {
        #expect(throws: KurrentJSONError.self) {
            try KurrentJSONDecoder().decode(StreamMetadata.StreamAcl.self, from: Data(#"{"$r":null}"#.utf8))
        }
    }

    @Test("Metadata holding \"$acl\":{} reads as .stream(.defaults), not .serverDefault")
    func testEmptyAclObjectIsNotServerDefault() throws {
        let metadata = try read(#"{"$acl":{}}"#)
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
        let metadata = try read(#"{"$acl":{"$r":["a"],"$w":"b","$mw":[]}}"#)
        guard case let .stream(acl) = metadata.acl else {
            Issue.record("Expected a stream ACL, got \(String(describing: metadata.acl)).")
            return
        }
        let updated = metadata.acl(.stream(acl.writeRoles(.defaults)))
        #expect(try json(updated) == #"{"$acl":{"$r":["a"],"$mw":[]}}"#)
    }

    @Test("Getters read .defaults for an absent permission and .granted([]) for an empty list")
    func testRolesGetters() throws {
        let metadata = try read(#"{"$acl":{"$mw":[]}}"#)
        guard case let .stream(acl) = metadata.acl else {
            Issue.record("Expected a stream ACL, got \(String(describing: metadata.acl)).")
            return
        }
        #expect(acl.metaWriteRoles == .granted([]))
        #expect(acl.readRoles == .defaults)
        #expect(acl != .defaults)
        #expect(acl == StreamMetadata.StreamAcl.defaults.metaWriteRoles([]))
    }

    @Test("A role written as a string equals one written as a one-element array, for the $acl keys only")
    func testRoleStringEqualsOneElementArray() throws {
        #expect(try read(#"{"$acl":{"$r":"a"}}"#) == read(#"{"$acl":{"$r":["a"]}}"#))
        #expect(try read(#"{"k":"a"}"#) != read(#"{"k":["a"]}"#))
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

    private func read(_ json: String) throws -> StreamMetadata {
        try StreamMetadata(data: Data(json.utf8))
    }

    /// The JSON `setMetadata` sends.
    private func json(_ metadata: StreamMetadata) throws -> String {
        try String(decoding: metadata.encoded(), as: UTF8.self)
    }

    private func object(of metadata: StreamMetadata) throws -> [String: PropertyValue] {
        try JSONDecoder().decode([String: PropertyValue].self, from: metadata.encoded())
    }

    private func object(of json: String) throws -> [String: PropertyValue] {
        try JSONDecoder().decode([String: PropertyValue].self, from: Data(json.utf8))
    }

    @Test("Every getter reads metadata written by another client, and it is written back the same")
    func testReadsOtherClientMetadata() throws {
        let metadata = try read(Self.otherClientJSON)
        #expect(metadata.maxCount == 10)
        #expect(metadata.maxAge == .seconds(60))
        #expect(metadata.truncateBefore == 5)
        #expect(metadata.cacheControl == .seconds(10))
        #expect(metadata.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["a"]).writeRoles(["b"])))
        #expect(try json(metadata) == Self.otherClientJSON)
    }

    @Test("A role written as a single string reads as a one-element list")
    func testAclSingleRoleString() throws {
        let metadata = try read(#"{"$acl":{"$r":"admin","$w":["ops","dev"]}}"#)
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
        let metadata = try read(#"{"$maxCount":9223372036854775807,"$tb":9223372036854775807}"#)
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
        // An $acl a later one replaces is still read member by member.
        #"{"$acl":{"$r":null},"$acl":{"$r":"ops"}}"#,
        #"{"$acl":{"$x":"a"},"$acl":{}}"#,
        #"{"$acl":{"$r":"2024-01-01T00:00:00"},"$acl":{"$r":"ops"}}"#,
        // A system key written with an escape.
        #"{"$maxCount":1.5}"#,
        // Text the server's JSON reader fails on, also in a value a later key replaces.
        #"{"custom":1e,"custom":0,"$maxCount":1}"#,
        #"{"custom":tru}"#,
        #"{"custom":"\x"}"#,
        #"{"custom":"unterminated}"#,
        #"{"$maxCount":1"#,
        #"{"a":1,,"b":2}"#,
        #"{"a":1 "b":2}"#,
        #"{"a":[1}"#,
        #"{"a":--1}"#,
        #"{"a":1.2.3}"#,
        #"{"a":.}"#,
    ])
    func testStrictReadingThrows(json: String) {
        #expect {
            try StreamMetadata(data: Data(json.utf8))
        } throws: { error in
            guard case .internalParsingError = error as? KurrentError else { return false }
            return true
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
        let metadata = try read(json)
        #expect(try read(self.json(metadata)) == metadata)
        #expect(try object(of: metadata) == object(of: self.json(read(self.json(metadata)))))
    }

    @Test("Negative and zero values read as stored and are written back; the server ignores those fields")
    func testIgnoredValues() throws {
        let stored = #"{"$maxCount":-1,"$maxAge":0,"$tb":-5,"$cacheControl":-5}"#
        let metadata = try read(stored)
        #expect(metadata.maxCount == nil)
        #expect(metadata.truncateBefore == nil)
        #expect(metadata.maxAge == .seconds(0))
        #expect(metadata.cacheControl == .seconds(-5))
        #expect(try json(metadata) == stored)
        let limits = try read(#"{"$maxAge":922337203685,"$cacheControl":-922337203685}"#)
        #expect(limits.maxAge == .seconds(922_337_203_685))
        #expect(limits.cacheControl == .seconds(-922_337_203_685))
    }

    // MARK: - Text encoding, as .NET's StreamReader decodes it

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

    private static let byteOrderMarked: [Data] = [
        Data([0xEF, 0xBB, 0xBF]) + Data(maxCountTwo.utf8),
        Data([0xFF, 0xFE]) + utf16(maxCountTwo, bigEndian: false),
        Data([0xFE, 0xFF]) + utf16(maxCountTwo, bigEndian: true),
        Data([0xFF, 0xFE, 0, 0]) + utf32(maxCountTwo, bigEndian: false),
        Data([0, 0, 0xFE, 0xFF]) + utf32(maxCountTwo, bigEndian: true),
    ]

    @Test("A byte order mark names the encoding, as the server's StreamReader detects it", arguments: byteOrderMarked)
    func testByteOrderMarks(data: Data) throws {
        #expect(try StreamMetadata(data: data).maxCount == 2)
    }

    @Test("Without a byte order mark the bytes are UTF-8, so UTF-16 text is a custom key holding NULs, as the server reads it", arguments: [
        utf16(maxCountTwo, bigEndian: false),
        utf16(maxCountTwo, bigEndian: true),
        utf32(maxCountTwo, bigEndian: true),
    ])
    func testUTF16WithoutByteOrderMark(data: Data) throws {
        let metadata = try StreamMetadata(data: data)
        #expect(metadata.maxCount == nil)
        #expect(try object(of: metadata).count == 1)
    }

    @Test("Malformed UTF-8 is replaced with U+FFFD, not refused, as the server's StreamReader replaces it")
    func testMalformedUTF8() throws {
        let metadata = try StreamMetadata(data: Data(#"{"$maxCount":3,"k":""#.utf8) + Data([0xFF]) + Data(#""}"#.utf8))
        #expect(metadata.maxCount == 3)
        #expect(try metadata.customProperty("k", as: String.self) == "\u{FFFD}")
    }

    @Test("The server stops reading at the object's closing brace: what follows is ignored and not kept", arguments: [
        Data(#"{"$maxCount":1} xyz"#.utf8),
        Data(#"{"$maxCount":1}{"$maxCount":"x"}"#.utf8),
        Data(#"{"$maxCount":1}"#.utf8) + Data([0xFF]),
        Data(#"{"$maxCount":1}"#.utf8) + Data([0xE4, 0xB8]),
    ])
    func testTrailingContent(data: Data) throws {
        let metadata = try StreamMetadata(data: data)
        #expect(metadata.maxCount == 1)
        #expect(try json(metadata) == #"{"$maxCount":1}"#)
    }

    // MARK: - Repeated keys and whitespace

    @Test("A trailing comma is accepted, as the server accepts it")
    func testTrailingCommas() throws {
        let repeated = try read(#"{"$maxCount":100,"$maxCount":2,}"#)
        #expect(repeated.maxCount == 2)
        #expect(try json(repeated) == #"{"$maxCount":2}"#)
        let kept = try read(#"{ "$acl" : { "$r" : [ "a" , ] , } , "k" : [ 1 , ] , }"#)
        #expect(try json(kept) == #"{"$acl":{"$r":["a"]},"k":[1]}"#)
        #expect(kept.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["a"])))
        let nested = try read(#"{"o":{"k":1,"k":2,},"a":[{"y":1,"y":3,},],}"#)
        #expect(try json(nested) == #"{"o":{"k":2},"a":[{"y":3}]}"#)
    }

    @Test("Keys that differ only in Unicode normalization are both read and both written back")
    func testCanonicallyEquivalentKeys() throws {
        let stored = "{\"caf\u{E9}\":1,\"cafe\u{301}\":2}"
        #expect(try read(stored).encoded() == Data(stored.utf8))
        // An escape denotes the same scalars as the character it stands for.
        let escaped = "{\"caf\\u00e9\":1,\"cafe\u{301}\":2,\"caf\u{E9}\":3}"
        #expect(try read(escaped).encoded() == Data("{\"cafe\u{301}\":2,\"caf\u{E9}\":3}".utf8))
    }

    @Test("A builder writes the system fields first and keeps every other member in its place")
    func testBuilderKeepsOtherMembers() throws {
        let metadata = try read(#"{"z":1,"$tb":3,"a":{"y":true, "b":null}}"#)
            .maxCount(2)
            .acl(.stream(StreamMetadata.StreamAcl.defaults.writeRoles(["w"]).readRoles(["r"])))
            .cacheControl(.seconds(5))
            .truncateBefore(4)
        #expect(try json(metadata) == #"{"$maxCount":2,"$tb":4,"$cacheControl":5,"$acl":{"$r":["r"],"$w":["w"]},"z":1,"a":{"y":true,"b":null}}"#)
    }

    @Test("A builder that does not set them keeps keys that differ only in Unicode normalization apart")
    func testBuilderKeepsCanonicallyEquivalentKeys() throws {
        let metadata = try read("{\"caf\u{E9}\":1,\"cafe\u{301}\":2,\"$acl\":{\"$r\":\"ops\"}}")
        #expect(try metadata.maxCount(2).encoded() == Data("{\"$maxCount\":2,\"$acl\":{\"$r\":[\"ops\"]},\"caf\u{E9}\":1,\"cafe\u{301}\":2}".utf8))
        #expect(try metadata.acl(.serverDefault).encoded() == Data("{\"caf\u{E9}\":1,\"cafe\u{301}\":2}".utf8))
    }

    @Test("Custom keys are Swift strings to the getter and the builder: either spelling names the key, and setting it replaces both")
    func testCustomKeysCompareAsStrings() throws {
        let metadata = try read("{\"caf\u{E9}\":1,\"cafe\u{301}\":2,\"z\":0}")
        #expect(try metadata.customProperty("caf\u{E9}", as: Int.self) == 1)
        #expect(try metadata.customProperty("cafe\u{301}", as: Int.self) == 1)
        let updated = try metadata.customProperty("cafe\u{301}", encoding: 3)
        #expect(try updated.encoded() == Data("{\"cafe\u{301}\":3,\"z\":0}".utf8))
        // The old value does not come back when the metadata is written and read again.
        #expect(try StreamMetadata(data: updated.encoded()).customProperty("caf\u{E9}", as: Int.self) == 3)
    }

    @Test("A builder keeps every digit of a number it does not set")
    func testBuilderKeepsNumbers() throws {
        let metadata = try read(#"{"ratio":1.234567890123456789,"big":123456789012345678901234567890,"e":6e1}"#)
            .maxAge(.seconds(60))
            .customProperty("tenant", encoding: "acme")
        #expect(try json(metadata) == #"{"$maxAge":60,"ratio":1.234567890123456789,"big":123456789012345678901234567890,"e":6e1,"tenant":"acme"}"#)
        #expect(try metadata.customProperty("ratio", as: Decimal.self) == Decimal(string: "1.234567890123456789"))
    }

    // MARK: - Nesting depth

    /// A metadata object whose `k` member nests arrays, so the text is `depth` levels deep.
    private static func nested(depth: Int) -> String {
        #"{"k":"# + String(repeating: "[", count: depth - 1) + String(repeating: "]", count: depth - 1) + "}"
    }

    @Test("Metadata nested 64 levels deep is read and written back")
    func testNestedAtTheLimit() throws {
        let metadata = try read(Self.nested(depth: 64))
        #expect(try json(metadata.maxCount(1)) == #"{"$maxCount":1,"# + Self.nested(depth: 64).dropFirst())
    }

    @Test("Metadata nested deeper than 64 levels throws instead of overflowing the stack", arguments: [65, 1_000, 100_000])
    func testNestedPastTheLimit(depth: Int) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: Data(Self.nested(depth: depth).utf8))
        }
    }

    // MARK: - Repeated keys

    @Test("A repeated top-level key reads as its last occurrence, as the server reads it, and a builder keeps it")
    func testRepeatedTopLevelKey() throws {
        let metadata = try read(#"{"$maxCount":2,"$maxCount":100}"#)
        #expect(metadata.maxCount == 100)
        #expect(try json(metadata) == #"{"$maxCount":100}"#)
        let rewritten = metadata.cacheControl(.seconds(5))
        #expect(rewritten.maxCount == 100)
        #expect(try json(rewritten) == #"{"$maxCount":100,"$cacheControl":5}"#)
    }

    @Test("Repeated keys read as their last occurrence", arguments: [
        // Inside $acl, where a string and an array may be mixed.
        (#"{"$acl":{"$r":"a","$w":"w","$r":["b"]}}"#, #"{"$acl":{"$r":["b"],"$w":["w"]}}"#),
        // Inside nested custom objects and arrays, with whitespace.
        (#"{ "o" : { "k" : 1 , "k" : { "x" : 1 , "x" : 2 } } , "a" : [ { "y" : 1 , "y" : 3 } , 4 ] }"#, #"{"o":{"k":{"x":2}},"a":[{"y":3},4]}"#),
        // The same key written with an escape.
        (#"{"$maxCount":1,"$maxCount":7}"#, #"{"$maxCount":7}"#),
        // A key holding an escaped quote.
        (#"{"a\"b":1,"c":2,"a\"b":3}"#, #"{"c":2,"a\"b":3}"#),
        // Strings holding braces, brackets, commas, colons and quoted keys.
        (#"{"s":"{\"$maxCount\":1}","$maxCount":3,"t":"}],:\\","$maxCount":4}"#, #"{"$maxCount":4,"s":"{\"$maxCount\":1}","t":"}],:\\"}"#),
    ])
    func testRepeatedNestedKeys(json: String, expected: String) throws {
        #expect(try self.json(read(json)) == expected)
    }

    @Test("A custom value reads its nested repeated key as the last occurrence")
    func testNestedRepeatedKeyInCustomValue() throws {
        let metadata = try read(#"{"o":{"k":1,"k":2}}"#)
        #expect(try metadata.customProperty("o", as: [String: Int].self) == ["k": 2])
        #expect(try metadata.customProperties(as: [String: [String: Int]].self) == ["o": ["k": 2]])
    }

    @Test("Custom values are written back as standard JSON with their content unchanged")
    func testCustomValuesAreKept() throws {
        let metadata = try read(#"{ "s" : "{\"k\":1,\"k\":2}" , "o" : { "k" : [ { "k" : 1 } ] } , "k" : -1.5e3 , "n" : null , "e" : { } , "l" : [ ] }"#)
        #expect(try json(metadata) == #"{"s":"{\"k\":1,\"k\":2}","o":{"k":[{"k":1}]},"k":-1.5e3,"n":null,"e":{},"l":[]}"#)
    }

    @Test("A repeated $acl role reaches the ACL as its last occurrence")
    func testRepeatedAclRole() throws {
        let metadata = try read(#"{"$acl":{"$r":"a","$r":["b","c"]}}"#)
        #expect(metadata.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["b", "c"])))
        let reversed = try read(#"{"$acl":{"$r":["b","c"],"$r":"a"}}"#)
        #expect(reversed.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["a"])))
    }

    @Test("A builder keeps unknown $ keys and custom keys")
    func testBuilderKeepsUnknownKeys() throws {
        let metadata = try read(#"{"$future":{"x":[1,true]},"tenant":"acme","$maxCount":5}"#).maxCount(1)
        #expect(try json(metadata) == #"{"$maxCount":1,"$future":{"x":[1,true]},"tenant":"acme"}"#)
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
        "",
    ])
    func testInitRejectsNonObject(json: String) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: Data(json.utf8))
        }
    }

    @Test("== compares every field, including maxCount")
    func testEqualityIncludesMaxCount() {
        #expect(StreamMetadata().maxCount(1) != StreamMetadata().maxCount(2))
    }

    @Test("== ignores key order and number spelling")
    func testEqualityIgnoresKeyOrder() throws {
        let lhs = try read(#"{"$maxCount":10,"tenant":"acme","$maxAge":60,"n":10}"#)
        let rhs = try read(#"{"$maxAge":60,"tenant":"acme","$maxCount":10,"n":1e1}"#)
        #expect(lhs == rhs)
        #expect(try lhs != rhs.customProperty("tenant", encoding: "other"))
        #expect(try lhs == rhs.customProperty("tenant", encoding: "acme"))
    }

    @Test("== reads keys that differ only in Unicode normalization as one key, the first")
    func testEqualityOfCanonicallyEquivalentKeys() throws {
        #expect(try read("{\"caf\u{E9}\":1}") == read("{\"cafe\u{301}\":1}"))
        #expect(try read("{\"caf\u{E9}\":1,\"cafe\u{301}\":2}") == read("{\"caf\u{E9}\":1}"))
        #expect(try read("{\"caf\u{E9}\":1,\"cafe\u{301}\":2}") != read("{\"caf\u{E9}\":2}"))
    }

    @Test("== compares values JSON cannot express by their content, whatever stands around them")
    func testEqualityOfNewtonsoftValues() throws {
        #expect(try read(#"{"o":{"a":NaN,"b":10}}"#) == read(#"{"o":{"b":1e1,"a":NaN}}"#))
        #expect(try read(#"{"o":{"a":NaN}}"#) != read(#"{"o":{"a":Infinity}}"#))
        #expect(try read(#"{"a":[undefined,1]}"#) == read(#"{"a":[,1]}"#))
        #expect(try read(#"{"d":new Date(1)}"#) == read(#"{"d":new Date( 1 )}"#))
    }

    @Test("== compares numbers a Double cannot hold as numbers", arguments: [
        ("1e400", "10e399", true),
        ("1e400", "1.0e400", true),
        ("1e400", "0.1e401", true),
        ("-1e400", "-10e399", true),
        ("1e400", "-1e400", false),
        ("1e400", "1e401", false),
        ("1e400", "2e400", false),
        // An exponent longer than Int holds, which the server's reader accepts.
        ("1e9223372036854775808", "10e9223372036854775807", true),
        ("1e9223372036854775808", "1e9223372036854775809", false),
        ("1e-9223372036854775809", "10e-9223372036854775810", true),
    ])
    func testEqualityOfHugeNumbers(lhs: String, rhs: String, equal: Bool) throws {
        #expect(try (read("{\"o\":{\"n\":\(lhs)}}") == read("{\"o\":{\"n\":\(rhs)}}")) == equal)
    }

    @Test("customProperties(encoding:) merges top-level keys")
    func testCustomPropertiesMerge() throws {
        let metadata = try read(#"{"tenant":"acme","retries":3}"#)
            .customProperties(encoding: ["tenant": "other", "env": "test"])
        #expect(try json(metadata) == #"{"tenant":"other","retries":3,"env":"test"}"#)
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

        let reread = try StreamMetadata(data: metadata.encoded())
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
        #expect(try StreamMetadata(data: single.encoded()).customProperty("k", as: PropertyValue.self) == Self.nestedArray(depth: 63))
        let merged = try StreamMetadata().customProperties(encoding: PropertyValue.object(["k": Self.nestedArray(depth: 63)]))
        #expect(try StreamMetadata(data: merged.encoded()) == single)
    }

    // MARK: - Dates, as Newtonsoft.Json reads strings

    @Test("Newtonsoft's date parsing: which strings are Date tokens, and which fail to convert", arguments: [
        ("2024-01-01T00:00:00", NewtonsoftDate.date),
        ("2024-01-01T00:00:00Z", .date),
        ("2024-01-01T00:00:00.1234567+08:00", .date),
        ("2024-01-01T00:00:00-0800", .date),
        ("2024-02-29T23:59:59", .date),
        ("2024-01-01T24:00:00", .date),
        // Seven fraction digits are read, and two more pass as a zone.
        ("2024-01-01T00:00:00.123456789", .date),
        ("2024-01-01T00:00:00.12345678", .notADate),
        ("2024-01-01T24:00:01", .notADate),
        ("2023-02-29T00:00:00", .notADate),
        ("0000-01-01T00:00:00", .notADate),
        ("2024-13-01T00:00:00", .notADate),
        ("2024-01-01", .notADate),
        ("2024-01-01 00:00:00", .notADate),
        ("2024-01-01T00:00:00 trailing", .notADate),
        ("ops", .notADate),
        ("", .notADate),
        // Adding the day 24:00:00 stands for passes DateTime.MaxValue.
        ("9999-12-31T24:00:00", .conversionFails),
        ("9999-12-31T24:00:00.000Z", .conversionFails),
        ("9999-12-31T23:59:59", .date),
        ("/Date(0)/", .date),
        ("/Date(1700000000000)/", .date),
        ("/Date(1700000000000+0800)/", .date),
        ("/Date(1700000000000-08)/", .date),
        ("/Date(-62135596800000)/", .date),
        ("/Date(253402300799999)/", .date),
        // Outside the years 1 to 9999.
        ("/Date(253402300800000)/", .conversionFails),
        ("/Date(-62135596800001)/", .conversionFails),
        ("/Date(1+080)/", .notADate),
        ("/Date(abc)/", .notADate),
        ("/Date()/", .notADate),
        ("/Date(99999999999999999999)/", .notADate),
        ("/Date(1)", .notADate),
    ])
    func testNewtonsoftDates(text: String, expected: NewtonsoftDate) {
        #expect(NewtonsoftDate.classify(text.utf16, bufferIndex: 0) == expected)
    }

    @Test("Whether a /Date(…)/ string with a malformed offset is a date depends on where the server's reader holds it, and that is reproduced")
    func testMicrosoftDatePosition() throws {
        // Newtonsoft checks the minutes of the offset only when `length - index in its buffer > 5`.
        // Unescaped, the string sits in the reader's buffer at its place in the text, the check is
        // skipped and ":0" passes as minutes; with an escape the reader copies it to index 0.
        #expect(NewtonsoftDate.classify("/Date(1+08:00)/".utf16, bufferIndex: 0) == .notADate)
        #expect(NewtonsoftDate.classify("/Date(1+08:00)/".utf16, bufferIndex: 16) == .date)
        #expect(NewtonsoftDate.classify("/Date(1+0800)/".utf16, bufferIndex: 0) == .date)
        #expect(NewtonsoftDate.classify("/Date(1+0800)/".utf16, bufferIndex: 16) == .date)

        #expect(throws: KurrentError.self) { try read(#"{"$acl":{"$r":"/Date(1+08:00)/"}}"#) }
        #expect(throws: KurrentError.self) { try read(#"{"c":"/Date(253402300800000+08:00)/"}"#) }
        let role = try read(#"{"$acl":{"$r":"\/Date(1+08:00)\/"}}"#)
        #expect(role.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["/Date(1+08:00)/"])))
        let custom = try read(#"{"c":"\/Date(253402300800000+08:00)/"}"#)
        #expect(try custom.customProperty("c", as: String.self) == "/Date(253402300800000+08:00)/")

        // Written with the first slash escaped, so the server reads it back as it was read here.
        #expect(try json(role) == #"{"$acl":{"$r":["\/Date(1+08:00)/"]}}"#)
        #expect(try read(json(role)) == role)
        #expect(try json(custom) == #"{"c":"\/Date(253402300800000+08:00)/"}"#)
        let built = StreamMetadata().acl(.stream(StreamMetadata.StreamAcl.defaults.readRoles(["/Date(1+08:00)/"])))
        #expect(try read(json(built)) == role)
    }

    @Test("A string that fails to convert as a date is refused wherever it stands, as the server fails on it", arguments: [
        #"{"$maxCount":1,"custom":"/Date(253402300800000)/"}"#,
        #"{"custom":{"deep":["/Date(253402300800000)/"]}}"#,
        #"{"custom":"/Date(253402300800000)/","custom":1}"#,
        #"{"custom":"9999-12-31T24:00:00"}"#,
        #"{"$future":"9999-12-31T24:00:00"}"#,
    ])
    func testDateConversionFailureThrows(json: String) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: Data(json.utf8))
        }
    }

    @Test("A custom string that reads as a date is kept as the string it is")
    func testCustomDateStringsAreKept() throws {
        let stored = #"{"at":"2024-01-01T00:00:00Z","ms":"/Date(0)/"}"#
        let metadata = try read(stored)
        #expect(try metadata.customProperty("at", as: String.self) == "2024-01-01T00:00:00Z")
        #expect(try json(metadata) == #"{"at":"2024-01-01T00:00:00Z","ms":"\/Date(0)/"}"#)
    }

    @Test("An $acl role that reads as a date is refused: the server's reader hands over a Date token", arguments: [
        #"{"$acl":{"$r":"2024-01-01T00:00:00"}}"#,
        #"{"$acl":{"$w":["ops","2024-01-01T00:00:00Z"]}}"#,
        #"{"$acl":{"$d":"/Date(0)/"}}"#,
    ])
    func testAclDateRoleThrows(json: String) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: Data(json.utf8))
        }
    }

    @Test("An $acl role that only resembles a date is a role name")
    func testAclRolesThatAreNotDates() throws {
        let metadata = try read(#"{"$acl":{"$r":["2024-01-01","2024-13-01T00:00:00","/Date(x)/"]}}"#)
        #expect(metadata.acl == .stream(StreamMetadata.StreamAcl.defaults.readRoles(["2024-01-01", "2024-13-01T00:00:00", "/Date(x)/"])))
    }

    @Test("Writing refuses what the server would ignore: a role that reads as a date, a custom string that fails to convert")
    func testEncodingRefusesWhatTheServerIgnores() throws {
        let dateRole = StreamMetadata().acl(.stream(StreamMetadata.StreamAcl.defaults.readRoles(["2024-01-01T00:00:00"])))
        let failing = try StreamMetadata().customProperty("custom", encoding: "/Date(253402300800000)/")
        let nested = try StreamMetadata().customProperty("custom", encoding: ["deep": ["9999-12-31T24:00:00"]])
        for metadata in [dateRole, failing, nested] {
            #expect {
                try metadata.encoded()
            } throws: { error in
                guard case .encodingError = error as? KurrentError else { return false }
                return true
            }
            #expect(String(reflecting: metadata).hasPrefix("StreamMetadata("))
        }
        // A custom string that converts is only a string to the server.
        #expect(try json(StreamMetadata().customProperty("at", encoding: "2024-01-01T00:00:00Z")) == #"{"at":"2024-01-01T00:00:00Z"}"#)
    }

    // MARK: - Numbers, as Newtonsoft.Json reads them

    @Test("A leading zero makes an octal or hexadecimal integer, as the server reads it", arguments: [
        (#"{"$maxCount":010}"#, #"{"$maxCount":8}"#),
        (#"{"$maxCount":0x10}"#, #"{"$maxCount":16}"#),
        (#"{"$maxCount":0X1f}"#, #"{"$maxCount":31}"#),
        (#"{"$maxCount":00}"#, #"{"$maxCount":0}"#),
        (#"{"$maxCount":-010}"#, #"{"$maxCount":-10}"#),
        // Convert.ToInt64 lets a non-decimal number set the sign bit.
        (#"{"$maxCount":0xFFFFFFFFFFFFFFFF}"#, #"{"$maxCount":-1}"#),
        (#"{"$maxCount":01777777777777777777777}"#, #"{"$maxCount":-1}"#),
        (#"{"n":010,"h":0x10}"#, #"{"n":8,"h":16}"#),
    ])
    func testOctalAndHexadecimal(json: String, expected: String) throws {
        #expect(try self.json(read(json)) == expected)
    }

    @Test("Leading zeros are no limit on an octal integer: 380 of them before a 1 is 1")
    func testOctalWithManyLeadingZeros() throws {
        #expect(try read(#"{"$maxCount":"# + String(repeating: "0", count: 380) + "1}").maxCount == 1)
    }

    @Test("Numbers the server's reader fails on", arguments: [
        #"{"$maxCount":09}"#,
        #"{"n":09}"#,
        #"{"n":0x}"#,
        #"{"n":0x1G}"#,
        #"{"n":0x10000000000000000}"#,
        #"{"n":02000000000000000000000}"#,
        #"{"n":01.5}"#,
        #"{"n":1e}"#,
        #"{"n":1x}"#,
        #"{"n":+1}"#,
        // An integer past Int64 is a BigInteger, refused past 380 characters.
        "{\"n\":" + String(repeating: "9", count: 381) + "}",
        // More than 19 digits is a BigInteger whatever its value, which is no long.
        #"{"$maxCount":-00000000000000000001}"#,
        #"{"$maxCount":NaN}"#,
        #"{"$maxCount":undefined}"#,
        #"{"$maxCount":new Date(1)}"#,
    ])
    func testNumbersTheServerFailsOn(json: String) {
        #expect(throws: KurrentError.self) {
            try StreamMetadata(data: Data(json.utf8))
        }
    }

    @Test("Custom numbers in spellings only the server's reader accepts are kept as standard JSON", arguments: [
        (#"{"n":.5}"#, #"{"n":0.5}"#, 0.5),
        (#"{"n":-.5}"#, #"{"n":-0.5}"#, -0.5),
        (#"{"n":1.}"#, #"{"n":1.0}"#, 1.0),
        (#"{"n":1.e2}"#, #"{"n":1.0e2}"#, 100.0),
        (#"{"n":-01.50}"#, #"{"n":-1.50}"#, -1.5),
        (#"{"n":1E+2}"#, #"{"n":1e+2}"#, 100.0),
        ("{\"n\":" + String(repeating: "9", count: 380) + "}", "{\"n\":" + String(repeating: "9", count: 380) + "}", Double.infinity),
    ])
    func testNonStandardNumbers(json: String, expected: String, value: Double) throws {
        let metadata = try read(json)
        #expect(try self.json(metadata) == expected)
        if value.isFinite {
            #expect(try metadata.customProperty("n", as: Double.self) == value)
        }
    }

    // MARK: - Syntax only Newtonsoft.Json reads

    @Test("Single quotes, unquoted keys and unescaped line breaks are read, and written back as standard JSON", arguments: [
        (#"{'$maxCount':1, tenant:'acme'}"#, #"{"$maxCount":1,"tenant":"acme"}"#),
        (#"{$maxCount:7,$acl:{$r:'ops'}}"#, #"{"$maxCount":7,"$acl":{"$r":["ops"]}}"#),
        (#"{'it''s':1}"#, nil),
        ("{\"k\":\"a\nb\tc\"}", #"{"k":"a\u000ab\u0009c"}"#),
        (#"{"k":'say "hi"'}"#, #"{"k":"say \"hi\""}"#),
        (#"{"k":"é😀\ud800x"}"#, "{\"k\":\"\u{E9}\u{1F600}\u{FFFD}x\"}"),
        ("{\u{A0}\"k\"\u{2003}:\u{0}1\u{0}}", #"{"k":1}"#),
    ] as [(String, String?)])
    func testNewtonsoftSyntax(json: String, expected: String?) throws {
        guard let expected else {
            #expect(throws: KurrentError.self) { try StreamMetadata(data: Data(json.utf8)) }
            return
        }
        #expect(try self.json(read(json)) == expected)
    }

    @Test("NaN, Infinity, undefined and constructors are kept as custom values and written back as they are")
    func testValuesJSONCannotExpress() throws {
        let metadata = try read(#"{"a":NaN,"b":-Infinity,"c":undefined,"d":[,1],"e":new Date( 1 , 'x' ),"f":Infinity,"g":,}"#)
        let written = #"{"a":NaN,"b":-Infinity,"c":undefined,"d":[undefined,1],"e":new Date(1,"x"),"f":Infinity,"g":undefined}"#
        #expect(try json(metadata) == written)
        #expect(try read(written) == metadata)
        #expect(throws: KurrentError.self) { try metadata.customProperty("a", as: Double.self) }
        // The builders still work around them.
        #expect(try json(metadata.maxCount(1)).hasPrefix(#"{"$maxCount":1,"a":NaN,"#))
    }

    @Test("A comment is read only inside the value of a custom key; anywhere the server reads tokens itself, it fails", arguments: [
        (#"{"k":{"a":1/*c*/,//x"# + "\n" + #""b":[1,/*c*/2]}}"#, #"{"k":{"a":1,"b":[1,2]}}"#),
        (#"{"k":[/**/]}"#, #"{"k":[]}"#),
        (#"/*c*/{}"#, nil),
        (#"{/*c*/}"#, nil),
        (#"{"$maxCount":1,/*x*/"$acl":{"$r":"ops"}}"#, nil),
        (#"{"k":/*c*/1}"#, nil),
        (#"{"k":1/*c*/}"#, nil),
        (#"{"k":[1]//c"# + "\n}", nil),
        (#"{"$acl":{/*c*/"$r":"a"}}"#, nil),
        (#"{"$acl":{"$r":["a"/*c*/]}}"#, nil),
        (#"{"$maxCount":/*c*/1}"#, nil),
        (#"{"k":{"a":1/*unterminated}}"#, nil),
    ] as [(String, String?)])
    func testComments(json: String, expected: String?) throws {
        guard let expected else {
            #expect(throws: KurrentError.self) { try StreamMetadata(data: Data(json.utf8)) }
            return
        }
        #expect(try self.json(read(json)) == expected)
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
