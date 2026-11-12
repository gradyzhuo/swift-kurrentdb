//
//  CustomMetadataTests.swift
//  swift-kurrentdb
//

import Foundation
import Testing
@testable import KurrentDB

@Suite("CustomMetadata")
struct CustomMetadataTests {
    struct OrderMetadata: Codable, Sendable, Equatable {
        var tenant: String
        var attempt: Int
    }

    private static func isDecodingError(_ error: any Error) -> Bool {
        guard case .decodingError = error as? KurrentError else { return false }
        return true
    }

    private static func isEncodingError(_ error: any Error) -> Bool {
        guard case .encodingError = error as? KurrentError else { return false }
        return true
    }

    private func recorded(customMetadata: Data) -> RecordedEvent {
        RecordedEvent(
            id: UUID(), eventType: "test", contentType: .json, streamIdentifier: .init(name: "orders"),
            revision: 0, position: .at(commitPosition: 0, preparePosition: 0),
            data: Data("{}".utf8), customMetadata: customMetadata
        )
    }

    // MARK: - JSON

    @Test(".json encodes a value, and decode reads it back")
    func jsonRoundTrip() throws {
        let metadata = try CustomMetadata.json(OrderMetadata(tenant: "acme", attempt: 2))
        #expect(metadata.format == .json)
        #expect(try JSONDecoder().decode(OrderMetadata.self, from: metadata.data) == OrderMetadata(tenant: "acme", attempt: 2))
        #expect(try metadata.decode(OrderMetadata.self) == OrderMetadata(tenant: "acme", attempt: 2))
    }

    @Test("decode ignores members the type does not declare, and fails on a missing one")
    func decodeAgainstOtherShapes() throws {
        let wider = try CustomMetadata(data: Data(#"{"tenant":"acme","attempt":2,"extra":[1,2]}"#.utf8), format: .json)
        #expect(try wider.decode(OrderMetadata.self) == OrderMetadata(tenant: "acme", attempt: 2))
        let narrower = try CustomMetadata(data: Data(#"{"tenant":"acme"}"#.utf8), format: .json)
        #expect { try narrower.decode(OrderMetadata.self) } throws: { Self.isDecodingError($0) }
    }

    @Test("Any JSON value is JSON metadata", arguments: [
        "{}", "[1,2]", "3", #""text""#, "true", "null", #"{"a":{"b":[1,{"c":null}]}}"#,
    ])
    func anyJSONValue(text: String) throws {
        #expect(try CustomMetadata(data: Data(text.utf8), format: .json).data == Data(text.utf8))
    }

    @Test("Bytes that are not JSON are refused as JSON metadata", arguments: [
        "", "not json", "{", #"{"a":}"#, "{} {}",
        "1e", "-", "[01]", "[1.]", "[.5]", "[+1]", "[NaN]", "[tru]", #"{"a":1e}"#,
        #"["\q"]"#, #"["\ud800"]"#, #"["\u12"]"#, "[\"a\tb\"]",
    ])
    func notJSON(text: String) {
        #expect { try CustomMetadata(data: Data(text.utf8), format: .json) } throws: { Self.isDecodingError($0) }
    }

    @Test("JSON metadata nests arrays and objects at most 64 levels deep")
    func nestingLimit() throws {
        // `depth` levels of arrays, of objects, or of the two in turn, around `leaf`.
        func arrays(_ depth: Int, _ leaf: String) -> Data {
            Data((String(repeating: "[", count: depth) + leaf + String(repeating: "]", count: depth)).utf8)
        }
        func objects(_ depth: Int, _ leaf: String) -> Data {
            Data((String(repeating: #"{"k":"#, count: depth - 1) + "{" + (leaf.isEmpty ? "" : #""k":"# + leaf) + String(repeating: "}", count: depth)).utf8)
        }
        func mixed(_ depth: Int, _ leaf: String) -> Data {
            Data((String(repeating: #"[{"k":"#, count: depth / 2) + (leaf.isEmpty ? "[]" : leaf) + String(repeating: "}]", count: depth / 2)).utf8)
        }
        for leaf in ["", "0", #""text""#, "null", "true"] {
            #expect(try CustomMetadata(data: arrays(64, leaf), format: .json).data == arrays(64, leaf))
            #expect(try CustomMetadata(data: objects(64, leaf), format: .json).data == objects(64, leaf))
            #expect { try CustomMetadata(data: arrays(65, leaf), format: .json) } throws: { Self.isDecodingError($0) }
            #expect { try CustomMetadata(data: objects(65, leaf), format: .json) } throws: { Self.isDecodingError($0) }
        }
        // 64 levels around a scalar; an empty array in its place is the 65th.
        #expect(try CustomMetadata(data: mixed(64, "0"), format: .json).data == mixed(64, "0"))
        #expect { try CustomMetadata(data: mixed(64, ""), format: .json) } throws: { Self.isDecodingError($0) }
    }

    @Test("A number outside Double is not JSON metadata, and is stored as bytes metadata")
    func numberOutsideDouble() throws {
        let data = Data(#"{"n":1e400}"#.utf8)
        #expect { try CustomMetadata(data: data, format: .json) } throws: { Self.isDecodingError($0) }
        let metadata = try CustomMetadata(data: data, format: .bytes)
        #expect(EventData(eventType: "test", model: ["k": "v"], customMetadata: metadata).customMetadata == data)
    }

    @Test("JSON metadata that is not an object is a decoding error for an EventRecord", arguments: [
        "[1,2]", "3", #""text""#, "true", "null",
    ])
    func notAnObjectForARecord(text: String) throws {
        let metadata = try CustomMetadata(data: Data(text.utf8), format: .json)
        #expect { try EventRecord(eventType: "test", payload: .json(["k": "v"]), customMetadata: metadata) } throws: { Self.isDecodingError($0) }
        #expect { try EventRecord(data: Data("{}".utf8), schema: .init(format: .json, name: "test"), customMetadata: metadata) } throws: { Self.isDecodingError($0) }
        // The metadata is reported before a payload that cannot be encoded.
        #expect { try EventRecord(eventType: "test", payload: .json(Double.nan), customMetadata: metadata) } throws: { Self.isDecodingError($0) }
    }

    @Test("A value that encodes to JSON nested too deep is an encoding error")
    func encodesTooDeep() {
        indirect enum Nested: Encodable, Sendable {
            case leaf
            case list(Nested)

            func encode(to encoder: any Encoder) throws {
                var container = encoder.unkeyedContainer()
                if case let .list(inner) = self {
                    try container.encode(inner)
                }
            }
        }
        let value = (0 ..< 65).reduce(Nested.leaf) { nested, _ in .list(nested) }
        #expect { try CustomMetadata.json(value) } throws: { Self.isEncodingError($0) }
    }

    @Test("A value JSONEncoder cannot write is an encoding error", arguments: [
        Double.nan, Double.infinity, -Double.infinity,
    ])
    func unencodableValue(value: Double) {
        #expect { try CustomMetadata.json(["n": value]) } throws: { Self.isEncodingError($0) }
    }

    // MARK: - Bytes

    @Test("Any bytes are bytes metadata")
    func anyBytes() throws {
        for bytes in [Data([0x00]), Data([0x00, 0xFF]), Data("not json".utf8)] {
            let metadata = try CustomMetadata(data: bytes, format: .bytes)
            #expect(metadata.data == bytes)
            #expect(metadata.format == .bytes)
        }
    }

    @Test("Empty bytes are refused, since they would read back as no metadata")
    func emptyBytes() {
        #expect { try CustomMetadata(data: Data(), format: .bytes) } throws: {
            guard case .initializationError = $0 as? KurrentError else { return false }
            return true
        }
    }

    // MARK: - Reading

    @Test("A recorded event's metadata is read in the format the reader names")
    func readRecorded() throws {
        let stored = Data(#"{"tenant":"acme","attempt":2}"#.utf8)
        let event = recorded(customMetadata: stored)
        #expect(try event.customMetadata(format: .json)?.decode(OrderMetadata.self) == OrderMetadata(tenant: "acme", attempt: 2))
        #expect(try event.customMetadata(format: .bytes)?.data == stored)
    }

    @Test("A recorded event without metadata has none in either format")
    func readRecordedWithoutMetadata() throws {
        let event = recorded(customMetadata: Data())
        #expect(try event.customMetadata(format: .json) == nil)
        #expect(try event.customMetadata(format: .bytes) == nil)
    }

    @Test("Stored bytes that are not JSON are refused as JSON and readable as bytes")
    func readRecordedBytes() throws {
        let event = recorded(customMetadata: Data([0x00, 0xFF]))
        #expect { try event.customMetadata(format: .json) } throws: { Self.isDecodingError($0) }
        #expect(try event.customMetadata(format: .bytes)?.data == Data([0x00, 0xFF]))
    }
}
