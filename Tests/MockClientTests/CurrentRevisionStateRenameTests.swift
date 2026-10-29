//
//  CurrentRevisionStateRenameTests.swift
//  MockClientTests
//

import Testing
@testable import KurrentDB

@Suite("CurrentRevisionState rename")
struct CurrentRevisionStateRenameTests {
    @Test("wrongExpectedVersion carries the server's state as CurrentRevisionState")
    func caseUsesCurrentRevision() {
        let error = KurrentError.wrongExpectedVersion(expected: .streamExists, current: .noStream)
        guard case let .wrongExpectedVersion(_, current) = error else {
            Issue.record("expected wrongExpectedVersion")
            return
        }
        let state: KurrentError.CurrentRevisionState = current
        if case .noStream = state {} else { Issue.record("expected .noStream, got \(state)") }
    }
}
