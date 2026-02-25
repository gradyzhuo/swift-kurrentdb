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
            .acl(.userStream)
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
}
