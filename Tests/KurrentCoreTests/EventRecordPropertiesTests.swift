//
//  EventRecordPropertiesTests.swift
//  swift-kurrentdb
//

import Foundation
import Testing
@testable import KurrentDB

@Suite("EventRecord properties")
struct EventRecordPropertiesTests {
    private static let payload = EventRecord.Payload.data(Data("{}".utf8), .json)

    private static func isDecodingError(_ error: any Error) -> Bool {
        (error as? KurrentError)?.cause is DecodingError
    }

    /// A record whose custom metadata is `customMetadata`, a JSON text, or one without metadata.
    private func makeRecord(customMetadata: String?) throws -> EventRecord {
        guard let customMetadata else {
            return try EventRecord(eventType: "test", payload: Self.payload)
        }
        return try EventRecord(eventType: "test", payload: Self.payload, customMetadata: CustomMetadata(data: Data(customMetadata.utf8), format: .json))
    }

    // MARK: - Parsing custom metadata

    @Test("A string-only object keeps every member")
    func stringOnlyObject() throws {
        let record = try makeRecord(customMetadata: #"{"operatorId":"op-1","tenant":"t"}"#)
        #expect(record.properties.count == 2)
        #expect(record.properties["operatorId"] as? String == "op-1")
        #expect(record.properties["tenant"] as? String == "t")
    }

    @Test("Integers, doubles, booleans, null, nested objects and arrays are all kept")
    func mixedObject() throws {
        let record = try makeRecord(customMetadata: #"{"count":3,"ratio":0.5,"flag":true,"off":false,"none":null,"nested":{"items":[1,"two",false]}}"#)
        #expect(record.properties.count == 6)
        #expect(record.properties["count"] as? Int == 3)
        #expect(record.properties["ratio"] as? Double == 0.5)
        #expect(record.properties["flag"] as? Bool == true)
        #expect(record.properties["off"] as? Bool == false)
        #expect(record.properties["none"] as? PropertyValue == .null)
        #expect(record.properties["nested"] as? PropertyValue == .object(["items": .array([.integer(1), .string("two"), .bool(false)])]))
    }

    @Test("An empty object and no metadata give no properties")
    func emptyMetadata() throws {
        #expect(try makeRecord(customMetadata: "{}").properties.isEmpty)
        #expect(try makeRecord(customMetadata: nil).properties.isEmpty)
        #expect(EventRecord(data: Data(), schema: .init(format: .json, name: "test")).properties.isEmpty)
    }

    @Test("JSON metadata that is not an object throws instead of being dropped", arguments: [
        "[1,2]", "3", #""text""#, "true", "null",
    ])
    func notAnObject(metadata: String) {
        #expect { try makeRecord(customMetadata: metadata) } throws: { Self.isDecodingError($0) }
    }

    @Test("A record created from bytes and a schema takes custom metadata too")
    func fromDataAndSchema() throws {
        let record = try EventRecord(data: Data("{}".utf8), schema: .init(format: .json, name: "test"), customMetadata: .json(["tenant": "acme"]))
        #expect(record.properties["tenant"] as? String == "acme")
        #expect { try EventRecord(data: Data(), schema: .init(format: .json, name: "test"), customMetadata: .json([1, 2])) } throws: { Self.isDecodingError($0) }
    }

    @Test("The deprecated Data? initializer reads a JSON object, and empty data or nil as no metadata")
    @available(*, deprecated)
    func deprecatedDataInitializer() throws {
        let record = try EventRecord(eventType: "test", payload: Self.payload, customMetadata: Data(#"{"operatorId":"op-1"}"#.utf8))
        #expect(record.properties["operatorId"] as? String == "op-1")
        #expect(try EventRecord(eventType: "test", payload: Self.payload, customMetadata: Data()).properties.isEmpty)
        #expect(try EventRecord(eventType: "test", payload: Self.payload, customMetadata: nil).properties.isEmpty)
        #expect(throws: DecodingError.self) {
            try EventRecord(eventType: "test", payload: Self.payload, customMetadata: Data("not json".utf8))
        }
        #expect(throws: DecodingError.self) {
            try EventRecord(eventType: "test", payload: Self.payload, customMetadata: Data(Self.nested(depth: 65).utf8))
        }
        // Invalid metadata is reported before a payload that cannot be encoded, as on 2.6.2.
        #expect(throws: DecodingError.self) {
            try EventRecord(eventType: "test", payload: .json(Double.nan), customMetadata: Data("[]".utf8))
        }
    }

    @Test("The deprecated properties setter stores a value without checking it")
    @available(*, deprecated)
    func deprecatedPropertiesSetter() throws {
        var record = try makeRecord(customMetadata: nil)
        record.properties["operatorId"] = "op-1"
        record.properties["n"] = Double.nan
        #expect(record.properties["operatorId"] as? String == "op-1")
        #expect(throws: KurrentError.self) { try record.protobufProperties() }
    }

    @Test("EventRecord(eventData:) carries the metadata of an EventData")
    func fromEventData() throws {
        let eventData = try EventData(eventType: "test", payload: .json(["a": "b"]), customMetadata: CustomMetadata(data: Data(#"{"operatorId":"op-1","n":7}"#.utf8), format: .bytes))
        let record = try EventRecord(eventData: eventData)
        #expect(record.properties["operatorId"] as? String == "op-1")
        #expect(record.properties["n"] as? Int == 7)
    }

    // MARK: - Sending properties

    @Test("Parsed metadata is sent as the matching google.protobuf.Value kinds")
    func protobufKinds() throws {
        let record = try makeRecord(customMetadata: #"{"s":"x","i":3,"d":0.5,"b":true,"z":null,"o":{"l":[1,false]}}"#)
        let fields = try record.protobufProperties()
        #expect(fields["s"]?.stringValue == "x")
        #expect(fields["i"]?.numberValue == 3)
        #expect(fields["d"]?.numberValue == 0.5)
        #expect(fields["b"]?.boolValue == true)
        #expect(fields["z"]?.kind == .nullValue(.nullValue))
        let list = try #require(fields["o"]?.structValue.fields["l"]?.listValue.values)
        #expect(list.count == 2)
        #expect(list[0].numberValue == 1)
        #expect(list[1].boolValue == false)
    }

    @Test("A property of any Codable type is encoded, not sent as null")
    @available(*, deprecated)
    func codableProperties() throws {
        struct Operator: Codable, Sendable {
            let id: String
            let level: Int
        }
        let record = try makeRecord(customMetadata: nil)
            .setValue(Int64(42), forKey: "int64")
            .setValue(UInt8(7), forKey: "uint8")
            .setValue(Operator(id: "op-1", level: 2), forKey: "operator")
            .setValue(String?.none, forKey: "missing")
        let fields = try record.protobufProperties()
        #expect(fields["int64"]?.numberValue == 42)
        #expect(fields["uint8"]?.numberValue == 7)
        #expect(fields["operator"]?.structValue.fields["id"]?.stringValue == "op-1")
        #expect(fields["operator"]?.structValue.fields["level"]?.numberValue == 2)
        #expect(fields["missing"]?.kind == .nullValue(.nullValue))
    }

    @Test("A large integer reaches v2 as the nearest Double and BatchAppend's JSON exactly")
    @available(*, deprecated)
    func largeIntegers() throws {
        let metadata = #"{"big":9007199254740993,"max":18446744073709551615,"over":9223372036854775809}"#
        let record = try makeRecord(customMetadata: metadata)
            .setValue(UInt64.max, forKey: "uint64")
            .setValue([UInt64.max], forKey: "nested")
        let fields = try record.protobufProperties()
        #expect(fields["big"]?.numberValue == 9007199254740992)
        #expect(fields["max"]?.numberValue == Double(UInt64.max))
        #expect(fields["over"]?.numberValue == Double(UInt64(9223372036854775809)))
        #expect(fields["uint64"]?.numberValue == Double(UInt64.max))
        #expect(fields["nested"]?.listValue.values.first?.numberValue == Double(UInt64.max))

        let json = try #require(try record.customMetadataJSON())
        let decoded = try JSONDecoder().decode([String: PropertyValue].self, from: json)
        #expect(decoded["big"] == .integer(9007199254740993))
        #expect(decoded["max"] == .unsignedInteger(.max))
        #expect(decoded["over"] == .unsignedInteger(9223372036854775809))
        #expect(decoded["uint64"] == .unsignedInteger(.max))
        #expect(decoded["nested"] == .array([.unsignedInteger(.max)]))
    }

    @Test("A large number with a fraction keeps it: never read as the integer it truncates to")
    func largeFraction() throws {
        let record = try makeRecord(customMetadata: #"{"n":9007199254740993.5,"m":-7.0}"#)
        // Read as a Double (the nearest, 9007199254740994), not truncated to the Int64 9007199254740993.
        #expect(record.properties["n"] as? Double == 9007199254740994)
        #expect(try record.protobufProperties()["n"]?.numberValue == 9007199254740994)
        #expect(record.properties["m"] as? Int == -7)
    }

    @Test("An integer beyond 64 bits fails both encodings")
    @available(*, deprecated)
    func integerBeyond64Bits() throws {
        let record = try makeRecord(customMetadata: nil).setValue(Int128(UInt64.max) + 1, forKey: "n")
        #expect(throws: KurrentError.self) { try record.protobufProperties() }
        #expect(throws: KurrentError.self) { try record.customMetadataJSON() }
    }

    @Test("A Double survives the JSON round trip of a nested property, however JSONEncoder writes it", arguments: [
        1e19, Double(UInt64(1) << 63), Double(UInt64(1) << 62), -Double(UInt64(1) << 62),
        1.2345678901234567e19, 9007199254740993.0, 0.1, -2.5e-300, 1.7976931348623157e308,
    ])
    @available(*, deprecated)
    func nestedDoubles(value: Double) throws {
        struct Measurement: Codable, Sendable {
            let value: Double
        }
        let record = try makeRecord(customMetadata: nil)
            .setValue([value], forKey: "values")
            .setValue(Measurement(value: value), forKey: "measurement")
        let fields = try record.protobufProperties()
        #expect(fields["values"]?.listValue.values.first?.numberValue == value)
        #expect(fields["measurement"]?.structValue.fields["value"]?.numberValue == value)

        let json = try #require(try record.customMetadataJSON())
        struct Echoed: Decodable {
            let values: [Double]
        }
        #expect(try JSONDecoder().decode(Echoed.self, from: json).values == [value])
    }

    @Test("A number in metadata, written in any form, reaches v2 as the Double it denotes", arguments: [
        "1e19", "10000000000000000000", "9.223372036854776e+18", "4.611686018427388e+18", "3e0", "0.1", "-7",
        "9007199254740993.5", "-9007199254740993.5", "12345678901234567890.25",
    ])
    func metadataNumberForms(literal: String) throws {
        let record = try makeRecord(customMetadata: #"{"n":\#(literal)}"#)
        let expected = try JSONDecoder().decode(Double.self, from: Data(literal.utf8))
        #expect(try record.protobufProperties()["n"]?.numberValue == expected)
    }

    @Test("NaN and infinite numbers fail both encodings", arguments: [
        Double.nan, Double.infinity, -Double.infinity,
    ])
    @available(*, deprecated)
    func nonFiniteNumbers(value: Double) throws {
        for record in [
            try makeRecord(customMetadata: nil).setValue(value, forKey: "n"),
            try makeRecord(customMetadata: nil).setValue(Float(value), forKey: "n"),
            try makeRecord(customMetadata: nil).setValue([value], forKey: "n"),
        ] {
            #expect(throws: KurrentError.self) { try record.protobufProperties() }
            #expect(throws: KurrentError.self) { try record.customMetadataJSON() }
        }
    }

    @Test("BatchAppend's custom metadata round-trips the parsed metadata")
    func batchAppendRoundTrip() throws {
        let metadata = #"{"s":"x","i":3,"d":0.5,"b":true,"z":null,"o":{"l":[1,false]}}"#
        let record = try makeRecord(customMetadata: metadata)
        let json = try #require(try record.customMetadataJSON())
        let decoded = try JSONDecoder().decode([String: PropertyValue].self, from: json)
        let expected = try JSONDecoder().decode([String: PropertyValue].self, from: Data(metadata.utf8))
        #expect(decoded == expected)
        #expect(try makeRecord(customMetadata: nil).customMetadataJSON() == nil)
    }

    // MARK: - Nesting depth

    /// A metadata object whose `k` member nests arrays, so the text is `depth` levels deep.
    private static func nested(depth: Int) -> String {
        #"{"k":"# + String(repeating: "[", count: depth - 1) + String(repeating: "]", count: depth - 1) + "}"
    }

    @Test("Metadata nested 64 levels deep is parsed")
    func nestedAtTheLimit() throws {
        let record = try makeRecord(customMetadata: Self.nested(depth: 64))
        let expected = (0 ..< 62).reduce(PropertyValue.array([])) { inner, _ in .array([inner]) }
        #expect(record.properties["k"] as? PropertyValue == expected)
    }

    @Test("Metadata nested 64 levels deep around a scalar is parsed")
    func nestedAtTheLimitAroundAScalar() throws {
        let text = #"{"k":"# + String(repeating: "[", count: 63) + "7" + String(repeating: "]", count: 63) + "}"
        let record = try makeRecord(customMetadata: text)
        let expected = (0 ..< 62).reduce(PropertyValue.array([.integer(7)])) { inner, _ in .array([inner]) }
        #expect(record.properties["k"] as? PropertyValue == expected)
    }

    @Test("Metadata nested deeper than 64 levels throws instead of overflowing the stack", arguments: [65, 1_000, 100_000])
    func nestedPastTheLimit(depth: Int) {
        #expect(throws: KurrentError.self) {
            try makeRecord(customMetadata: Self.nested(depth: depth))
        }
    }
}
