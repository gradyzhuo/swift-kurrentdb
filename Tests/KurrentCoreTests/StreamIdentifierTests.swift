//
//  StreamIdentifierTests.swift
//  swift-kurrentdb
//

import Testing
@testable import KurrentDB

@Suite("StreamIdentifier Tests")
struct StreamIdentifierTests {

    // MARK: - Name & Encoding

    @Test("Name is stored correctly")
    func testNameIsStored() {
        let id = StreamIdentifier(name: "orders")
        #expect(id.name == "orders")
    }

    @Test("Default encoding is UTF-8")
    func testDefaultEncoding() {
        let id = StreamIdentifier(name: "test")
        #expect(id.encoding == .utf8)
    }

    @Test("Custom encoding is preserved")
    func testCustomEncoding() {
        let id = StreamIdentifier(name: "test", encoding: .ascii)
        #expect(id.encoding == .ascii)
    }

    // MARK: - Category extraction

    @Test("Category extracted from 'category-id' format", arguments: [
        ("order-12345",    "order"),
        ("payment-abc",    "payment"),
        ("account-1",      "account"),
        ("user-profile-x", "user"),  // Only the first segment before the first hyphen
    ])
    func testCategoryExtraction(name: String, expected: String) {
        let id = StreamIdentifier(name: name)
        #expect(id.category == expected)
    }

    @Test("Category is nil for names without a hyphen")
    func testNoCategoryForSimpleName() {
        let id = StreamIdentifier(name: "orders")
        #expect(id.category == nil)
    }

    @Test("Category is nil for names beginning with a hyphen")
    func testNoCategoryForLeadingHyphen() {
        let id = StreamIdentifier(name: "-special")
        #expect(id.category == nil)
    }

    // MARK: - Equality

    @Test("Equal names and encodings are equal")
    func testEqualityMatch() {
        let a = StreamIdentifier(name: "orders")
        let b = StreamIdentifier(name: "orders")
        #expect(a == b)
    }

    @Test("Different names are not equal")
    func testEqualityMismatchName() {
        let a = StreamIdentifier(name: "orders")
        let b = StreamIdentifier(name: "payments")
        #expect(a != b)
    }

    @Test("Same name but different encoding are not equal")
    func testEqualityMismatchEncoding() {
        let a = StreamIdentifier(name: "orders", encoding: .utf8)
        let b = StreamIdentifier(name: "orders", encoding: .ascii)
        #expect(a != b)
    }

    // MARK: - ExpressibleByStringLiteral

    @Test("String literal produces correct identifier")
    func testStringLiteralConformance() {
        let id: StreamIdentifier = "orders"
        #expect(id.name == "orders")
    }

    // MARK: - Static properties

    @Test("StreamIdentifier.all has name '$all'")
    func testAllStreamIdentifier() {
        #expect(StreamIdentifier.all.name == "$all")
    }
}
