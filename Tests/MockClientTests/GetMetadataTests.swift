//
//  GetMetadataTests.swift
//  swift-kurrentdb
//
//  No server needed: the fake node of InProcessKurrentDB.swift answers the read of `$$<stream>`.
//

import Foundation
import Testing
@testable import KurrentDB

@Suite("getMetadata on a fake node")
struct GetMetadataTests {
    private typealias Message = Streams<SpecifiedStream>.Read.UnderlyingResponse

    /// An event message the client cannot turn into an event (it has no id): it reads as
    /// `.unserviceable(link: nil)`.
    private static let unserviceable = Message.with {
        $0.event = .with { $0.event = .with { _ in } }
    }

    private static func metadataEvent(_ json: String, contentType: String = "application/json") -> Message {
        .with {
            $0.event = .with {
                $0.event = .with {
                    $0.id = .with { $0.value = .string(UUID().uuidString) }
                    $0.streamIdentifier = .with { $0.streamName = Data("$$orders".utf8) }
                    $0.metadata = [
                        "type": "$metadata",
                        "content-type": contentType,
                        "created": "17612345678901234",
                    ]
                    $0.data = Data(json.utf8)
                }
            }
        }
    }

    private func metadata(after messages: [Message]) async throws -> StreamMetadata? {
        let fake = InProcessKurrentDB(read: .init(messages: messages, ending: .end))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        return try await client.streams(specified: "orders").getMetadata()
    }

    @Test("getMetadata skips a response that is not an event and returns the metadata event after it")
    func skipsNonEventResponses() async throws {
        let json = #"{"$maxCount":7,"tenant":"acme"}"#
        let metadata = try #require(try await metadata(after: [Self.unserviceable, Self.metadataEvent(json)]))
        #expect(metadata.maxCount == 7)
        #expect(try metadata.encoded() == Data(json.utf8))
    }

    @Test("getMetadata returns nil when the read holds no event")
    func noEvent() async throws {
        #expect(try await metadata(after: [Self.unserviceable]) == nil)
        #expect(try await metadata(after: []) == nil)
    }

    @Test("getMetadata throws internalParsingError for metadata the server ignores, such as a 2.x client's [high, low] duration", arguments: [
        #"{"$maxCount":2,"$maxAge":[3,4659767778871345152]}"#,
        #"{"$maxCount":2,"$acl":"$userStreamAcl"}"#,
    ])
    func invalidSystemKey(json: String) async throws {
        await #expect {
            try await metadata(after: [Self.metadataEvent(json)])
        } throws: { error in
            guard case .internalParsingError = error as? KurrentError else { return false }
            return true
        }
    }

    @Test("getMetadata throws internalParsingError for a metadata event that is not JSON")
    func notJSON() async throws {
        await #expect {
            try await metadata(after: [Self.metadataEvent("{}", contentType: "application/octet-stream")])
        } throws: { error in
            guard case .internalParsingError = error as? KurrentError else { return false }
            return true
        }
    }
}
