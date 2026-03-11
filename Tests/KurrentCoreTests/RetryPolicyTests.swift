//
//  RetryPolicyTests.swift
//  KurrentCoreTests
//

@testable import KurrentDB
import Testing

// Counter helper: @unchecked Sendable is safe here because withRetry calls
// closures sequentially within a single async task, never concurrently.
private final class Counter: @unchecked Sendable {
    var value: Int = 0
    func increment() { value += 1 }
}

@Suite("OperationRetryPolicy")
struct RetryPolicyTests {

    // MARK: - Duration.multiplied(by:)

    @Test("multiplied(by: 2.0) doubles the duration")
    func testMultipliedDoubles() {
        let d = Duration.milliseconds(100)
        #expect(d.multiplied(by: 2.0) == .milliseconds(200))
    }

    @Test("multiplied(by: 0.5) halves the duration")
    func testMultipliedHalves() {
        let d = Duration.milliseconds(200)
        #expect(d.multiplied(by: 0.5) == .milliseconds(100))
    }

    @Test("multiplied(by: 0) returns zero")
    func testMultipliedByZero() {
        let d = Duration.milliseconds(500)
        #expect(d.multiplied(by: 0.0) == .zero)
    }

    @Test("multiplied(by: 1.0) is identity")
    func testMultipliedByOne() {
        let d = Duration.seconds(3)
        #expect(d.multiplied(by: 1.0) == .seconds(3))
    }

    @Test("multiplied handles large durations without overflow")
    func testMultipliedLargeDuration() {
        // 10 seconds × 2.0 = 20 seconds
        let d = Duration.seconds(10)
        #expect(d.multiplied(by: 2.0) == .seconds(20))
    }

    // MARK: - OperationRetryPolicy.default

    @Test("default policy has expected values")
    func testDefaultPolicy() {
        let policy = OperationRetryPolicy.default
        #expect(policy.maxAttempts == 3)
        #expect(policy.initialDelay == .milliseconds(100))
        #expect(policy.maxDelay == .seconds(10))
        #expect(policy.multiplier == 2.0)
        if case .full = policy.jitter {
            // pass
        } else {
            Issue.record("Expected jitter to be .full")
        }
    }

    // MARK: - ClientSettings integration

    @Test("ClientSettings.localhost() has backward-compatible policy (maxAttempts: 2, no delay)")
    func testDefaultClientSettingsIsBackwardCompatible() {
        let settings = ClientSettings.localhost()
        #expect(settings.operationRetryPolicy.maxAttempts == 2)
        #expect(settings.operationRetryPolicy.initialDelay == .zero)
        #expect(settings.operationRetryPolicy.maxDelay == .zero)
    }

    @Test("operationRetryPolicy builder sets the policy")
    func testClientSettingsBuilder() {
        let settings = ClientSettings.localhost()
            .operationRetryPolicy(.default)
        #expect(settings.operationRetryPolicy.maxAttempts == 3)
        #expect(settings.operationRetryPolicy.initialDelay == .milliseconds(100))
    }

    @Test("operationRetryPolicy builder supports custom policy")
    func testClientSettingsBuilderCustom() {
        let policy = OperationRetryPolicy(
            maxAttempts: 5,
            initialDelay: .milliseconds(200),
            maxDelay: .seconds(30),
            multiplier: 1.5,
            jitter: .none
        )
        let settings = ClientSettings.localhost().operationRetryPolicy(policy)
        #expect(settings.operationRetryPolicy.maxAttempts == 5)
        #expect(settings.operationRetryPolicy.maxDelay == .seconds(30))
        #expect(settings.operationRetryPolicy.multiplier == 1.5)
    }

    // MARK: - withRetry logic

    @Test("succeeds on first attempt without calling invalidate")
    func testSuccessOnFirstAttempt() async throws {
        let selectCalled = Counter()
        let invalidateCalled = Counter()
        let operationCalled = Counter()

        let policy = OperationRetryPolicy(
            maxAttempts: 3,
            initialDelay: .zero,
            maxDelay: .zero,
            multiplier: 1.0,
            jitter: .none
        )

        let result: String = try await withRetry(
            policy: policy,
            selectNode: { selectCalled.increment(); return "node-1" },
            invalidate: { invalidateCalled.increment() }
        ) { node in
            operationCalled.increment()
            return "success:\(node)"
        }

        #expect(result == "success:node-1")
        #expect(selectCalled.value == 1)
        #expect(operationCalled.value == 1)
        #expect(invalidateCalled.value == 0)
    }

    @Test("retries on node failure and succeeds on second attempt")
    func testRetryOnNodeFailure() async throws {
        let invalidateCalled = Counter()
        let attempts = Counter()

        let policy = OperationRetryPolicy(
            maxAttempts: 3,
            initialDelay: .zero,
            maxDelay: .zero,
            multiplier: 1.0,
            jitter: .none
        )

        let result: String = try await withRetry(
            policy: policy,
            selectNode: { "node" },
            invalidate: { invalidateCalled.increment() }
        ) { node in
            attempts.increment()
            if attempts.value == 1 {
                throw KurrentError.grpcConnectionError(cause: .init(code: .unavailable, message: "down"))
            }
            return "ok"
        }

        #expect(result == "ok")
        #expect(attempts.value == 2)
        #expect(invalidateCalled.value == 1)
    }

    @Test("exhausts maxAttempts and rethrows the last error")
    func testExhaustsMaxAttempts() async throws {
        let invalidateCalled = Counter()
        let attempts = Counter()

        let policy = OperationRetryPolicy(
            maxAttempts: 3,
            initialDelay: .zero,
            maxDelay: .zero,
            multiplier: 1.0,
            jitter: .none
        )

        var thrownError: KurrentError?
        do throws(KurrentError) {
            let _: String = try await withRetry(
                policy: policy,
                selectNode: { "node" },
                invalidate: { invalidateCalled.increment() }
            ) { _ in
                attempts.increment()
                throw KurrentError.deadlineExceeded
            }
        } catch {
            thrownError = error
        }

        #expect(attempts.value == 3)
        #expect(invalidateCalled.value == 2)  // invalidated after attempt 1 and 2
        #expect(thrownError == .deadlineExceeded)
    }

    @Test("maxAttempts: 1 means no retry")
    func testNoRetryWhenMaxAttemptsIsOne() async throws {
        let invalidateCalled = Counter()
        let attempts = Counter()

        let policy = OperationRetryPolicy(
            maxAttempts: 1,
            initialDelay: .zero,
            maxDelay: .zero,
            multiplier: 1.0,
            jitter: .none
        )

        var thrownError: KurrentError?
        do throws(KurrentError) {
            let _: String = try await withRetry(
                policy: policy,
                selectNode: { "node" },
                invalidate: { invalidateCalled.increment() }
            ) { _ in
                attempts.increment()
                throw KurrentError.grpcConnectionError(cause: .init(code: .unavailable, message: "down"))
            }
        } catch {
            thrownError = error
        }

        #expect(attempts.value == 1)
        #expect(invalidateCalled.value == 0)
        if case .grpcConnectionError = thrownError {
            // pass
        } else {
            Issue.record("Expected .grpcConnectionError, got \(String(describing: thrownError))")
        }
    }

    @Test("non-node-failure errors are not retried")
    func testNonNodeFailureNotRetried() async throws {
        let attempts = Counter()
        let invalidateCalled = Counter()

        let policy = OperationRetryPolicy(
            maxAttempts: 5,
            initialDelay: .zero,
            maxDelay: .zero,
            multiplier: 1.0,
            jitter: .none
        )

        var thrownError: KurrentError?
        do throws(KurrentError) {
            let _: String = try await withRetry(
                policy: policy,
                selectNode: { "node" },
                invalidate: { invalidateCalled.increment() }
            ) { _ in
                attempts.increment()
                throw KurrentError.accessDenied   // isNodeFailure == false
            }
        } catch {
            thrownError = error
        }

        #expect(attempts.value == 1)
        #expect(invalidateCalled.value == 0)
        #expect(thrownError == .accessDenied)
    }

    @Test("default ClientSettings maxAttempts:2 retries exactly once (legacy parity)")
    func testLegacyParity() async throws {
        let attempts = Counter()
        let invalidateCalled = Counter()

        let settings = ClientSettings.localhost()
        let policy = settings.operationRetryPolicy

        var thrownError: KurrentError?
        do throws(KurrentError) {
            let _: String = try await withRetry(
                policy: policy,
                selectNode: { "node" },
                invalidate: { invalidateCalled.increment() }
            ) { _ in
                attempts.increment()
                throw KurrentError.notLeaderException
            }
        } catch {
            thrownError = error
        }

        #expect(attempts.value == 2)           // 1 initial + 1 retry
        #expect(invalidateCalled.value == 1)   // invalidated after first failure
        #expect(thrownError == .notLeaderException)
    }
}
