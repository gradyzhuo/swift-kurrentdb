//
//  StreamFilterTests.swift
//  swift-kurrentdb
//

import Testing
@testable import KurrentDB

@Suite("StreamFilter Tests")
struct StreamFilterTests {

    // MARK: - Event type filters

    @Test("onEventType(regex:) sets type and regex")
    func testEventTypeRegex() {
        let filter = StreamFilter.onEventType(regex: "^Order.*")
        #expect(filter.type == .eventType)
        #expect(filter.regex == "^Order.*")
        #expect(filter.prefixes.isEmpty)
    }

    @Test("onEventType(prefixes:) via variadic sets type and prefixes")
    func testEventTypePrefixVariadic() {
        let filter = StreamFilter.onEventType(prefixes: "Order", "Payment")
        #expect(filter.type == .eventType)
        #expect(filter.prefixes.contains("Order"))
        #expect(filter.prefixes.contains("Payment"))
        #expect(filter.regex == nil)
    }

    @Test("onEventType(prefixes:) via array sets correct count")
    func testEventTypePrefixArray() {
        let filter = StreamFilter.onEventType(prefixes: ["A", "B", "C"])
        #expect(filter.prefixes.count == 3)
    }

    // MARK: - Stream name filters

    @Test("onStreamName(regex:) sets type and regex")
    func testStreamNameRegex() {
        let filter = StreamFilter.onStreamName(regex: "^orders-.*")
        #expect(filter.type == .streamName)
        #expect(filter.regex == "^orders-.*")
        #expect(filter.prefixes.isEmpty)
    }

    @Test("onStreamName(prefix:) variadic sets type and prefix")
    func testStreamNamePrefixVariadic() {
        let filter = StreamFilter.onStreamName(prefix: "orders")
        #expect(filter.type == .streamName)
        #expect(filter.prefixes.contains("orders"))
    }

    @Test("onStreamName(prefixes:) array accepts multiple prefixes")
    func testStreamNameMultiplePrefixes() {
        let filter = StreamFilter.onStreamName(prefixes: ["orders", "payments", "accounts"])
        #expect(filter.prefixes.count == 3)
        #expect(filter.prefixes.contains("accounts"))
    }

    // MARK: - excludeSystemEvents

    @Test("excludeSystemEvents sets streamName type with a non-nil regex")
    func testExcludeSystemEventsType() {
        let filter = StreamFilter.excludeSystemEvents()
        #expect(filter.type == .streamName)
        #expect(filter.regex != nil)
    }

    @Test("excludeSystemEvents regex does not match system streams starting with $")
    func testExcludeSystemEventsRegexExcludes$Prefix() throws {
        let filter = StreamFilter.excludeSystemEvents()
        let regex = try #require(filter.regex)
        // The regex should not match "$et-OrderPlaced" (system stream)
        let systemStream = "$et-OrderPlaced"
        let range = systemStream.range(of: regex, options: .regularExpression)
        #expect(range == nil)
    }

    @Test("excludeSystemEvents regex matches user streams not starting with $")
    func testExcludeSystemEventsRegexAllowsUserStreams() throws {
        let filter = StreamFilter.excludeSystemEvents()
        let regex = try #require(filter.regex)
        let userStream = "orders-123"
        let range = userStream.range(of: regex, options: .regularExpression)
        #expect(range != nil)
    }

    // MARK: - Window

    @Test("Default window is .count")
    func testDefaultWindowIsCount() {
        let filter = StreamFilter.onEventType(regex: ".*")
        if case .count = filter.window {
            // pass
        } else {
            Issue.record("Expected .count window, got \(filter.window)")
        }
    }

    @Test("max() sets window to .max with given count")
    func testMaxWindow() {
        let filter = StreamFilter.onEventType(regex: ".*").max(100)
        if case let .max(count) = filter.window {
            #expect(count == 100)
        } else {
            Issue.record("Expected .max(100) window, got \(filter.window)")
        }
    }

    // MARK: - Builder methods

    @Test("add(prefix:) appends a prefix to existing prefixes")
    func testAddPrefix() {
        let filter = StreamFilter.onStreamName(prefixes: ["orders"])
            .add(prefix: "payments")
        #expect(filter.prefixes.count == 2)
        #expect(filter.prefixes.contains("payments"))
    }

    @Test("checkpointIntervalMultiplier() sets the multiplier")
    func testCheckpointIntervalMultiplier() {
        let filter = StreamFilter.onEventType(regex: ".*").checkpointIntervalMultiplier(5)
        #expect(filter.checkpointIntervalMultiplier == 5)
    }

    @Test("Builder methods do not mutate the original")
    func testBuilderImmutability() {
        let original = StreamFilter.onEventType(prefixes: ["Order"])
        let modified = original.add(prefix: "Payment")
        #expect(original.prefixes.count == 1)
        #expect(modified.prefixes.count == 2)
    }
}
