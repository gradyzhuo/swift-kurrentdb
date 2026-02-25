//
//  ProjectionStatusTests.swift
//  swift-kurrentdb
//

import Testing
@testable import KurrentDB

@Suite("Projection.Status Tests")
struct ProjectionStatusTests {

    // MARK: - Single status

    @Test("'Running' status contains .running")
    func testRunning() {
        let status = Projection.Status(rawValue: "Running")
        #expect(status.contains(.running))
        #expect(!status.contains(.stopped))
    }

    @Test("'Stopped' status contains .stopped")
    func testStopped() {
        let status = Projection.Status(rawValue: "Stopped")
        #expect(status.contains(.stopped))
        #expect(!status.contains(.running))
    }

    @Test("'Faulted' status contains .faulted")
    func testFaulted() {
        let status = Projection.Status(rawValue: "Faulted")
        #expect(status.contains(.faulted))
    }

    @Test("'Initial' status contains .initial")
    func testInitial() {
        let status = Projection.Status(rawValue: "Initial")
        #expect(status.contains(.initial))
    }

    // MARK: - Compound status (slash-separated)

    @Test("'Aborted/Stopped' contains both .aborted and .stopped")
    func testAbortedStopped() {
        let status = Projection.Status(rawValue: "Aborted/Stopped")
        #expect(status.contains(.aborted))
        #expect(status.contains(.stopped))
        #expect(!status.contains(.running))
    }

    @Test("'Stopped/Faulted' contains both .stopped and .faulted")
    func testStoppedFaulted() {
        let status = Projection.Status(rawValue: "Stopped/Faulted")
        #expect(status.contains(.stopped))
        #expect(status.contains(.faulted))
    }

    // MARK: - contains([Name])

    @Test("contains([Name]) returns true when all names are present")
    func testContainsMultipleAllPresent() {
        let status = Projection.Status(rawValue: "Aborted/Stopped")
        #expect(status.contains([.aborted, .stopped]))
    }

    @Test("contains([Name]) returns false when any name is absent")
    func testContainsMultipleSomeAbsent() {
        let status = Projection.Status(rawValue: "Aborted/Stopped")
        #expect(!status.contains([.aborted, .stopped, .running]))
    }

    // MARK: - names array

    @Test("names array is parsed correctly from rawValue", arguments: [
        ("Running",          [Projection.Status.Name.running]),
        ("Stopped",          [Projection.Status.Name.stopped]),
        ("Aborted/Stopped",  [Projection.Status.Name.aborted, .stopped]),
        ("Stopped/Faulted",  [Projection.Status.Name.stopped, .faulted]),
    ])
    func testNamesArray(rawValue: String, expected: [Projection.Status.Name]) {
        let status = Projection.Status(rawValue: rawValue)
        for name in expected {
            #expect(status.names.contains(name))
        }
        #expect(status.names.count == expected.count)
    }

    // MARK: - rawValue preservation

    @Test("rawValue is preserved as-is")
    func testRawValuePreserved() {
        let raw = "Aborted/Stopped"
        let status = Projection.Status(rawValue: raw)
        #expect(status.rawValue == raw)
    }

    @Test("'Running results' suffix is stripped before parsing names")
    func testResultsSuffixIsIgnored() {
        let status = Projection.Status(rawValue: "Running results")
        #expect(status.contains(.running))
        #expect(status.names.count == 1)
    }

    // MARK: - Unknown values

    @Test("Unrecognised rawValue yields empty names array")
    func testUnknownStatus() {
        let status = Projection.Status(rawValue: "SomeUnknownState")
        #expect(status.names.isEmpty)
    }

    // MARK: - All known names round-trip

    @Test("Every known status Name round-trips through rawValue", arguments: [
        Projection.Status.Name.running,
        .stopped,
        .faulted,
        .initial,
        .writing,
        .completed,
        .suspended,
        .loadStateRequested,
        .stateLoaded,
        .subscribed,
        .faultedStopping,
        .stopping,
        .completingPhase,
        .phaseCompleted,
        .aborted,
    ])
    func testAllKnownNamesRoundtrip(name: Projection.Status.Name) {
        let status = Projection.Status(rawValue: name.rawValue)
        #expect(status.contains(name))
    }
}
