//
//  DeleteWrongExpectedVersionTests.swift
//  MockClientTests
//

import GRPCCore
import Testing
@testable import KurrentDB

@Suite("Wrong expected version on delete and tombstone")
struct DeleteWrongExpectedVersionTests {
    private func rejection(exception: String = "wrong-expected-version", actual: String?) -> RPCError {
        var metadata = Metadata()
        metadata.addString(exception, forKey: "exception")
        metadata.addString("orders-1", forKey: "stream-name")
        metadata.addString("-4", forKey: "expected-version")
        if let actual { metadata.addString(actual, forKey: "actual-version") }
        return RPCError(code: .failedPrecondition, message: "Delete failed due to WrongExpectedVersion.", metadata: metadata)
    }

    @Test("A missing stream is reported as current .noStream, with the caller's expectation")
    func missingStream() {
        let error = KurrentError.wrongExpectedVersion(from: rejection(actual: "-1"), expected: .streamExists)
        guard case let .wrongExpectedVersion(expected, current)? = error else {
            Issue.record("expected wrongExpectedVersion, got \(String(describing: error))")
            return
        }
        guard case .streamExists = expected else { Issue.record("expected .streamExists, got \(expected)"); return }
        guard case .noStream = current else { Issue.record("expected .noStream, got \(current)"); return }
    }

    @Test("An existing stream is reported at its revision", arguments: [(StreamRevision.at(5), UInt64?(5)), (StreamRevision.noStream, UInt64?.none)])
    func existingStream(expectedRevision: StreamRevision, expectedNumber: UInt64?) {
        let error = KurrentError.wrongExpectedVersion(from: rejection(actual: "0"), expected: expectedRevision)
        guard case let .wrongExpectedVersion(expected, current)? = error else {
            Issue.record("expected wrongExpectedVersion, got \(String(describing: error))")
            return
        }
        switch (expected, expectedNumber) {
        case let (.revision(number), expectedNumber?): #expect(number == expectedNumber)
        case (.noStream, nil): break
        default: Issue.record("unexpected expectation \(expected)")
        }
        guard case .revision(0) = current else { Issue.record("expected .revision(0), got \(current)"); return }
    }

    @Test("An actual version that is not a revision or -1 is not mapped", arguments: ["", "abc", "-4", "-5"])
    func unknownActualVersion(actual: String) {
        #expect(KurrentError.wrongExpectedVersion(from: rejection(actual: actual), expected: .any) == nil)
    }

    @Test("A rejection without the actual-version trailer is not mapped")
    func missingActualVersion() {
        #expect(KurrentError.wrongExpectedVersion(from: rejection(actual: nil), expected: .any) == nil)
    }

    @Test("Other server exceptions are not mapped")
    func otherException() {
        #expect(KurrentError.wrongExpectedVersion(from: rejection(exception: "stream-deleted", actual: "-1"), expected: .any) == nil)
    }
}
