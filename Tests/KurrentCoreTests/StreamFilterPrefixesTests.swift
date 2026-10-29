//
//  StreamFilterPrefixesTests.swift
//  KurrentCoreTests
//

@testable import KurrentDB
import Testing

@Suite("StreamFilter.onStreamName(prefixes:)")
struct StreamFilterPrefixesTests {
    @Test("One prefix resolves to the prefixes: overload and matches like the array form")
    func singlePrefixIsTheVariadicOverload() {
        let variadic = StreamFilter.onStreamName(prefixes: "orders-")
        let array = StreamFilter.onStreamName(prefixes: ["orders-"])
        #expect(variadic.prefixes == array.prefixes)
        #expect(variadic.prefixes == ["orders-"])
    }
}
