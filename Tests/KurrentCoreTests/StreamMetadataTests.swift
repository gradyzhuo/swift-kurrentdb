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

    @Test("Default StreamMetadata has all nil values")
    func testDefaultIsAllNil() {
        let metadata = StreamMetadata()
        #expect(metadata.maxCount == nil)
        #expect(metadata.maxAge == nil)
        #expect(metadata.truncateBefore == nil)
        #expect(metadata.cacheControl == nil)
        #expect(metadata.acl == nil)
        #expect(metadata.customProperties == nil)
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

    @Test("acl builder sets userStream")
    func testAclUserStream() {
        let metadata = StreamMetadata().acl(.userStream)
        #expect(metadata.acl == .userStream)
    }

    @Test("acl builder sets systemStream")
    func testAclSystemStream() {
        let metadata = StreamMetadata().acl(.systemStream)
        #expect(metadata.acl == .systemStream)
    }

    @Test("customProperties builder sets value")
    func testCustomProperties() {
        let props = ["env": "test", "owner": "team-a"]
        let metadata = StreamMetadata().customProperties(props)
        #expect(metadata.customProperties == props)
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
            .acl(.userStream)
        #expect(metadata.maxCount == 200)
        #expect(metadata.maxAge == .seconds(86400))
        #expect(metadata.cacheControl == .seconds(5))
        #expect(metadata.acl == .userStream)
    }

    // MARK: - Codable

    @Test("JSON roundtrip preserves all set values")
    func testJSONRoundtrip() throws {
        let original = StreamMetadata()
            .maxCount(10)
            .maxAge(.seconds(300))
            .truncateBefore(4)
            .cacheControl(.seconds(7))
            .acl(.stream(StreamMetadata.StreamAcl().readRoles(["$admins"]).writeRoles(["ops", "writer"])))
            .customProperties(["owner": "team-a"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StreamMetadata.self, from: data)
        #expect(decoded == original)
    }

    // MARK: - Acl Codable

    @Test("userStream ACL encodes and decodes correctly")
    func testUserStreamAclRoundtrip() throws {
        let encoded = try JSONEncoder().encode(StreamMetadata.Acl.userStream)
        let decoded = try JSONDecoder().decode(StreamMetadata.Acl.self, from: encoded)
        #expect(decoded == .userStream)
    }

    @Test("systemStream ACL encodes and decodes correctly")
    func testSystemStreamAclRoundtrip() throws {
        let encoded = try JSONEncoder().encode(StreamMetadata.Acl.systemStream)
        let decoded = try JSONDecoder().decode(StreamMetadata.Acl.self, from: encoded)
        #expect(decoded == .systemStream)
    }

    // MARK: - StreamAcl builder

    @Test("StreamAcl readRoles builder sets value")
    func testStreamAclReadRoles() {
        let acl = StreamMetadata.StreamAcl().readRoles(["admin", "reader"])
        #expect(acl.readRoles == ["admin", "reader"])
    }

    @Test("StreamAcl writeRoles builder sets value")
    func testStreamAclWriteRoles() {
        let acl = StreamMetadata.StreamAcl().writeRoles(["admin"])
        #expect(acl.writeRoles == ["admin"])
    }

    @Test("StreamAcl deleteRoles builder sets value")
    func testStreamAclDeleteRoles() {
        let acl = StreamMetadata.StreamAcl().deleteRoles(["admin"])
        #expect(acl.deleteRoles == ["admin"])
    }

    @Test("StreamAcl metaReadRoles builder sets value")
    func testStreamAclMetaReadRoles() {
        let acl = StreamMetadata.StreamAcl().metaReadRoles(["admin"])
        #expect(acl.metaReadRoles == ["admin"])
    }

    @Test("StreamAcl metaWriteRoles builder sets value")
    func testStreamAclMetaWriteRoles() {
        let acl = StreamMetadata.StreamAcl().metaWriteRoles(["admin"])
        #expect(acl.metaWriteRoles == ["admin"])
    }

    @Test("StreamAcl builder is immutable")
    func testStreamAclBuilderImmutability() {
        let original = StreamMetadata.StreamAcl()
        let modified = original.readRoles(["admin"])
        #expect(original.readRoles == nil)
        #expect(modified.readRoles == ["admin"])
    }
    // MARK: - The server's format

    private func json(_ metadata: StreamMetadata) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try String(decoding: encoder.encode(metadata), as: UTF8.self)
    }

    private func decode(_ json: String) throws -> StreamMetadata {
        try JSONDecoder().decode(StreamMetadata.self, from: Data(json.utf8))
    }

    @Test("Durations are written as whole seconds, the sub-second part dropped")
    func testDurationsAreWholeSeconds() throws {
        let metadata = StreamMetadata()
            .maxCount(5)
            .maxAge(.seconds(60))
            .truncateBefore(2)
            .cacheControl(.milliseconds(10_900))
        #expect(try json(metadata) == #"{"$cacheControl":10,"$maxAge":60,"$maxCount":5,"$tb":2}"#)
    }

    @Test("userStream writes no $acl, so the server applies its $userStreamAcl default")
    func testUserStreamWritesNoAcl() throws {
        #expect(try json(StreamMetadata().maxAge(.seconds(60)).acl(.userStream)) == #"{"$maxAge":60}"#)
    }

    @Test("systemStream writes the server's built-in $systemStreamAcl")
    func testSystemStreamWritesAdmins() throws {
        #expect(try json(StreamMetadata().acl(.systemStream)) == #"{"$acl":{"$d":["$admins"],"$mr":["$admins"],"$mw":["$admins"],"$r":["$admins"],"$w":["$admins"]}}"#)
    }

    @Test("A stream ACL is written as an object of role arrays, unset permissions left out")
    func testStreamAclWritesObject() throws {
        let acl = StreamMetadata.StreamAcl().readRoles(["ops"]).metaWriteRoles(["$admins"])
        #expect(try json(StreamMetadata().acl(.stream(acl))) == #"{"$acl":{"$mw":["$admins"],"$r":["ops"]}}"#)
    }

    @Test("Values the server ignores the whole object for are refused", arguments: [
        StreamMetadata().maxCount(UInt64(Int64.max) + 1),
        StreamMetadata().truncateBefore(.max),
        StreamMetadata().maxAge(.seconds(62_000_000_001)),
        StreamMetadata().cacheControl(.seconds(922_337_203_686)),
        StreamMetadata().cacheControl(.seconds(-922_337_203_686)),
    ])
    func testOutOfRangeThrows(metadata: StreamMetadata) {
        #expect(throws: EncodingError.self) {
            try JSONEncoder().encode(metadata)
        }
    }

    @Test("The largest values the server applies are written")
    func testLimitsAreWritten() throws {
        let metadata = StreamMetadata()
            .maxCount(UInt64(Int64.max))
            .maxAge(.seconds(62_000_000_000))
            .cacheControl(.seconds(922_337_203_685))
        #expect(try json(metadata) == #"{"$cacheControl":922337203685,"$maxAge":62000000000,"$maxCount":9223372036854775807}"#)
    }

    @Test("Metadata in the server's format is read")
    func testReadsServerFormat() throws {
        let metadata = try decode(#"{"$maxCount":5,"$maxAge":60,"$tb":2,"$cacheControl":10,"$acl":{"$r":"$all","$w":["ops","writer"]},"$tmp":true,"other":1}"#)
        #expect(metadata.maxCount == 5)
        #expect(metadata.maxAge == .seconds(60))
        #expect(metadata.truncateBefore == 2)
        #expect(metadata.cacheControl == .seconds(10))
        #expect(metadata.acl == .stream(StreamMetadata.StreamAcl().readRoles(["$all"]).writeRoles(["ops", "writer"])))
    }

    @Test("Metadata 2.6.1 and earlier wrote is still read")
    func testReadsLegacyFormat() throws {
        // 2.6.1 encoded a Duration with its synthesized Codable.
        let maxAge = try String(decoding: JSONEncoder().encode(Duration.seconds(60)), as: UTF8.self)
        let cacheControl = try String(decoding: JSONEncoder().encode(Duration.milliseconds(3500)), as: UTF8.self)
        let legacy = try decode(#"{"$maxAge":\#(maxAge),"$cacheControl":\#(cacheControl),"$acl":"$systemStreamAcl"}"#)
        #expect(legacy.maxAge == .seconds(60))
        #expect(legacy.cacheControl == .milliseconds(3500))
        #expect(legacy.acl == .systemStream)
        #expect(try decode(#"{"$acl":"$userStreamAcl"}"#).acl == .userStream)
    }

    @Test("null reads as unset, as it did in 2.6.1")
    func testNullReadsAsUnset() throws {
        let metadata = try decode(#"{"$maxCount":null,"$maxAge":null,"$cacheControl":null,"$acl":{"$r":null,"$w":"ops"}}"#)
        #expect(metadata == StreamMetadata().acl(.stream(StreamMetadata.StreamAcl().writeRoles(["ops"]))))
    }

    @Test("== compares maxCount")
    func testEqualityComparesMaxCount() {
        #expect(StreamMetadata().maxCount(1) != StreamMetadata().maxCount(2))
    }
}
