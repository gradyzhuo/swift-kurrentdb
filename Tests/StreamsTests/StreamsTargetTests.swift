//
//  StreamsTargetTests.swift
//  KurrentDB
//
//  Created by Claude Code on 2026/2/14.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("StreamsTarget Tests", .serialized)
struct StreamsTargetTests: Sendable {
    // MARK: - SpecifiedStream Tests

    @Test("SpecifiedStream should be created with StreamIdentifier")
    func testSpecifiedStreamWithIdentifier() {
        let identifier = StreamIdentifier(name: "test-stream")
        let target = SpecifiedStream.specified(identifier)

        #expect(target.identifier.name == "test-stream")
        #expect(target.identifier.encoding == .utf8)
    }

    @Test("SpecifiedStream should be created with name string")
    func testSpecifiedStreamWithName() {
        let target = SpecifiedStream.specified("my-stream")

        #expect(target.identifier.name == "my-stream")
        #expect(target.identifier.encoding == .utf8)
    }

    @Test("SpecifiedStream should be created with name and custom encoding")
    func testSpecifiedStreamWithCustomEncoding() {
        let target = SpecifiedStream.specified("my-stream", encoding: .ascii)

        #expect(target.identifier.name == "my-stream")
        #expect(target.identifier.encoding == .ascii)
    }

    @Test("SpecifiedStream should support string literal initialization")
    func testSpecifiedStreamStringLiteral() {
        let target: SpecifiedStream = "literal-stream"

        #expect(target.identifier.name == "literal-stream")
        #expect(target.identifier.encoding == .utf8)
    }

    // MARK: - AllStreamsTarget Tests

    @Test("AllStreamsTarget should be created via static property")
    func testAllStreamsTarget() {
        let target = AllStreamsTarget.all

        // Verify type at compile time - if this compiles, the type is correct
        #expect(type(of: target) == AllStreamsTarget.self)
    }

    // MARK: - MultiStreamsTarget Tests

    @Test("MultiStreamsTarget should be created via static property")
    func testMultiStreamsTarget() {
        let target = MultiStreamsTarget.multiple

        // Verify type at compile time - if this compiles, the type is correct
        #expect(type(of: target) == MultiStreamsTarget.self)
    }

    // MARK: - ProjectionStream Tests

    @Test("ProjectionStream should be created by event type")
    func testProjectionStreamByEventType() {
        let target = ProjectionStream.byEventType("UserCreated")

        #expect(target.identifier.name == "$et-UserCreated")
    }

    @Test("ProjectionStream should be created by stream prefix")
    func testProjectionStreamByStreamPrefix() {
        let target = ProjectionStream.byStream(prefix: "user")

        #expect(target.identifier.name == "$ce-user")
    }

    // MARK: - String Conformance Tests

    @Test("String should conform to SpecifiedStreamTarget")
    func testStringConformance() {
        let streamName = "string-stream"
        let identifier = streamName.identifier

        #expect(identifier.name == "string-stream")
        #expect(identifier.encoding == .utf8)
    }

    // MARK: - AnyStreamTarget Tests

    @Test("AnyStreamTarget should be instantiable")
    func testAnyStreamTarget() {
        let target = AnyStreamTarget()

        // Verify type - conformance to StreamsTarget is checked at compile time
        #expect(type(of: target) == AnyStreamTarget.self)
    }

    // MARK: - Integration with KurrentDBClient Tests

    @Test("KurrentDBClient should accept SpecifiedStream target")
    func testClientWithSpecifiedStream() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = client.streams(of: .specified("test-stream"))

        #expect(streams.target.identifier.name == "test-stream")
    }

    @Test("KurrentDBClient should accept AllStreamsTarget target")
    func testClientWithAllStreamsTarget() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = client.streams(of: .all)

        // Verify the target type
        #expect(type(of: streams.target) == AllStreamsTarget.self)
    }

    @Test("KurrentDBClient should accept MultiStreamsTarget target",
          .enabled(if: ProcessInfo.processInfo.environment["KURRENTDB_SUPPORTS_MULTI_STREAMS"] == "true"))
    func testClientWithMultiStreamsTarget() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = client.streams(of: .multiple)

        // Verify the target type
        #expect(type(of: streams.target) == MultiStreamsTarget.self)
    }

    @Test("KurrentDBClient should accept ProjectionStream target by event type")
    func testClientWithProjectionStreamByEventType() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = client.streams(of: .byEventType("OrderPlaced"))

        #expect(streams.target.identifier.name == "$et-OrderPlaced")
    }

    @Test("KurrentDBClient should accept ProjectionStream target by stream prefix")
    func testClientWithProjectionStreamByPrefix() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = client.streams(of: .byStream(prefix: "order"))

        #expect(streams.target.identifier.name == "$ce-order")
    }

    @Test("KurrentDBClient convenience methods should work with stream names")
    func testClientConvenienceMethods() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        // Test specified stream convenience method
        let specifiedStreams = client.streams(specified: "my-stream")
        #expect(specifiedStreams.target.identifier.name == "my-stream")

        // Test allStreams convenience property
        let allStreams = client.allStreams
        #expect(type(of: allStreams.target) == AllStreamsTarget.self)

        // Test multiStreams convenience property
        let multiStreams = client.multiStreams
        #expect(type(of: multiStreams.target) == MultiStreamsTarget.self)
    }

    // MARK: - Type Safety Tests

    @Test("Different StreamsTarget types should be distinct")
    func testStreamsTargetTypeDistinction() {
        let specified: SpecifiedStream = .specified("stream")
        let all: AllStreamsTarget = .all
        let multiple: MultiStreamsTarget = .multiple

        // These should all be different types
        #expect(type(of: specified) == SpecifiedStream.self)
        #expect(type(of: all) == AllStreamsTarget.self)
        #expect(type(of: multiple) == MultiStreamsTarget.self)
    }

    @Test("SpecifiedStreamTarget subtypes should have identifiers")
    func testSpecifiedStreamTargetIdentifiers() {
        let specified: SpecifiedStream = .specified("test")
        let projection: ProjectionStream = .byEventType("Event")
        let string = "string-stream"

        // All should have valid identifiers
        #expect(specified.identifier.name == "test")
        #expect(projection.identifier.name == "$et-Event")
        #expect(string.identifier.name == "string-stream")

        // Verify they all conform to SpecifiedStreamTarget protocol
        // (This is verified at compile time by accessing .identifier property)
        let targets: [any SpecifiedStreamTarget] = [specified, projection, string]
        #expect(targets.count == 3)
    }

    // MARK: - Edge Cases

    @Test("SpecifiedStream should handle empty stream name")
    func testSpecifiedStreamWithEmptyName() {
        let target: SpecifiedStream = .specified("")

        #expect(target.identifier.name == "")
    }

    @Test("SpecifiedStream should handle special characters in stream name")
    func testSpecifiedStreamWithSpecialCharacters() {
        let specialName = "stream-with-special_chars@123"
        let target: SpecifiedStream = .specified(specialName)

        #expect(target.identifier.name == specialName)
    }

    @Test("ProjectionStream should handle special characters in event type")
    func testProjectionStreamWithSpecialEventType() {
        let eventType = "User.Created.V2"
        let target: ProjectionStream = .byEventType(eventType)

        #expect(target.identifier.name == "$et-User.Created.V2")
    }

    @Test("ProjectionStream should handle special characters in stream prefix")
    func testProjectionStreamWithSpecialPrefix() {
        let prefix = "user_stream"
        let target: ProjectionStream = .byStream(prefix: prefix)

        #expect(target.identifier.name == "$ce-user_stream")
    }
}
