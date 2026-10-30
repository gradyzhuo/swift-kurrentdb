//
//  WithRetryTests.swift
//  MockClientTests
//

import Synchronization
import Testing
@testable import KurrentDB

@Suite("withRetry")
struct WithRetryTests {
    private var twoAttempts: OperationRetryPolicy { var p = OperationRetryPolicy.default; p.maxAttempts = 2; p.initialDelay = .zero; return p }

    @Test("A node failure the predicate rejects is thrown at once, without invalidate() and without a second attempt")
    func predicateRejectsRetry() async throws {
        let attempts = Mutex(0), invalidations = Mutex(0)
        await #expect(throws: KurrentError.deadlineExceeded) {
            try await withRetry(policy: twoAttempts, isRetryable: { $0 != .deadlineExceeded },
                                selectNode: { 1 }, invalidate: { invalidations.withLock { $0 += 1 } }) { _ in
                attempts.withLock { $0 += 1 }
                throw KurrentError.deadlineExceeded
            }
        }
        #expect(attempts.withLock { $0 } == 1)
        #expect(invalidations.withLock { $0 } == 0)
    }

    @Test("The default predicate retries a node failure once and invalidates the node in between")
    func defaultPredicateRetriesNodeFailures() async throws {
        let attempts = Mutex(0), invalidations = Mutex(0)
        await #expect(throws: KurrentError.deadlineExceeded) {
            try await withRetry(policy: twoAttempts, selectNode: { 1 }, invalidate: { invalidations.withLock { $0 += 1 } }) { _ in
                attempts.withLock { $0 += 1 }
                throw KurrentError.deadlineExceeded
            }
        }
        #expect(attempts.withLock { $0 } == 2)
        #expect(invalidations.withLock { $0 } == 1)
    }
}
