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

    // MARK: - AllStreams Tests

    @Test("AllStreams should be created via static property")
    func testAllStreams() {
        let target = AllStreams.all

        // Verify type at compile time - if this compiles, the type is correct
        #expect(type(of: target) == AllStreams.self)
    }

    // MARK: - MultiStreams Tests

    @Test("MultiStreams should be created via static property")
    func testMultiStreams() {
        let target = MultiStreams.multiple

        // Verify type at compile time - if this compiles, the type is correct
        #expect(type(of: target) == MultiStreams.self)
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
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = await client.streams(of: .specified("test-stream"))

        await #expect(streams.target.identifier.name == "test-stream")
    }

    @Test("KurrentDBClient should accept AllStreams target")
    func testClientWithAllStreams() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = await client.streams(of: AllStreams.all)

        // Verify the target type
        await #expect(type(of: streams.target) == AllStreams.self)
    }

    @Test("KurrentDBClient should accept MultiStreams target")
    func testClientWithMultiStreams() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = await client.streams(of: MultiStreams.multiple)

        // Verify the target type
        await #expect(type(of: streams.target) == MultiStreams.self)
    }

    @Test("KurrentDBClient should accept ProjectionStream target by event type")
    func testClientWithProjectionStreamByEventType() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = await client.streams(of: ProjectionStream.byEventType("OrderPlaced"))

        await #expect(streams.target.identifier.name == "$et-OrderPlaced")
    }

    @Test("KurrentDBClient should accept ProjectionStream target by stream prefix")
    func testClientWithProjectionStreamByPrefix() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        let streams = await client.streams(of: ProjectionStream.byStream(prefix: "order"))

        await #expect(streams.target.identifier.name == "$ce-order")
    }

    @Test("KurrentDBClient convenience methods should work with stream names")
    func testClientConvenienceMethods() async {
        let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .cerificate(source: .crtInBundle("ca", inBundle: .module)!)
        let client = KurrentDBClient(settings: settings)

        // Test specified stream convenience method
        let specifiedStreams = await client.streams(specified: "my-stream")
        await #expect(specifiedStreams.target.identifier.name == "my-stream")

        // Test allStreams convenience property
        let allStreams = await client.allStreams
        await #expect(type(of: allStreams.target) == AllStreams.self)

        // Test multiStreams convenience property
        let multiStreams = await client.multiStreams
        await #expect(type(of: multiStreams.target) == MultiStreams.self)
    }

    // MARK: - Type Safety Tests

    @Test("Different StreamsTarget types should be distinct")
    func testStreamsTargetTypeDistinction() {
        let specified: SpecifiedStream = .specified("stream")
        let all: AllStreams = .all
        let multiple: MultiStreams = .multiple

        // These should all be different types
        #expect(type(of: specified) == SpecifiedStream.self)
        #expect(type(of: all) == AllStreams.self)
        #expect(type(of: multiple) == MultiStreams.self)
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
