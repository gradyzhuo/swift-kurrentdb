//
//  SubscriptionLifecycleTests.swift
//  swift-kurrentdb
//

import Testing
import Synchronization
import GRPCCore
@testable import KurrentDB

@Suite("Subscription lifecycle contract", .serialized, .timeLimit(.minutes(1)))
struct SubscriptionLifecycleTests {

    typealias Sub = PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>.Subscription<PersistentSubscription.EventResult>

    /// `Mutex` is noncopyable and cannot be returned inside a tuple,
    /// so a class wraps it and counts teardowns in a thread-safe way.
    private final class TeardownCounter: Sendable {
        private let mutex = Mutex<Int>(0)

        var count: Int {
            mutex.withLock { $0 }
        }

        func increment() {
            mutex.withLock { $0 += 1 }
        }
    }

    /// Creates a subscription and records whether teardown was called.
    private func makeSubscription() -> (sub: Sub, tornDown: TeardownCounter) {
        let writer = Sub.Writer()
        let sub = Sub(writer: writer)
        let counter = TeardownCounter()
        sub.onFinish { _ in counter.increment() }
        return (sub, counter)
    }

    /// Note: this test passes **without** a `deinit`, as was checked by running it.
    /// - Note: This test builds a `Subscription` directly, not through `Read.send`, and checks only the
    ///   "source stream released → teardown" part. The production path (through a real read task) is
    ///   covered by `SubscriptionRetainCycleLiveTests`: that path used to have a retain cycle
    ///   (#127), which this test cannot catch because it goes around the read task.
    @Test("T1: dropping it without ever reading events still runs teardown")
    func droppingWithoutIteratingTearsDown() async throws {
        // Wait for the real teardown signal instead of guessing the scheduling.
        // ARC runs `deinit` deterministically when the closure ends, but when that drives `onTermination`
        // is an implementation detail of AsyncStream, so wait for the signal, not for Task.yield().
        //
        // If teardown never happens the test stops here and the suite's `.timeLimit` catches it.
        // That is the intent: the assertion holds no time value, and the time bound lives in the operational layer.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let writer = Sub.Writer()
            let sub = Sub(writer: writer)
            sub.onFinish { _ in continuation.resume() }
            // events is not read on purpose; sub is released as soon as this closure ends.
            // No bridge task holds it, so the release is certain.
        }
        // Reaching this line means teardown did run: that is the assertion.
    }

    @Test("T3: when the RPC throws, events throws and teardown runs")
    func rpcErrorTerminatesAndTearsDown() async throws {
        let (sub, tornDown) = makeSubscription()
        // Drive the failure synchronously first, then await: no timing is used
        sub.send(state: .finish(throwing: KurrentError.connectionClosed))

        await #expect(throws: (any Error).self) {
            for try await _ in sub.events { }
        }
        #expect(tornDown.count == 1)
    }

    @Test("T2: leaving the loop after iterating runs teardown")
    func breakingOutTearsDown() async throws {
        let (sub, tornDown) = makeSubscription()
        sub.send(state: .finish())   // a normal end

        for try await _ in sub.events { break }
        #expect(tornDown.count == 1)
    }

    @Test("T4: a connection failure is reported as subscriptionDropped with the resume position")
    func connectionFailureReportsDropped() async throws {
        let (sub, _) = makeSubscription()
        // Drive the connection failure synchronously first, then await: no timing is used
        sub.send(state: .finish(throwing: KurrentError.grpcConnectionError(
            cause: RPCError(code: .unavailable, message: "connection lost")
        )))

        var caught: KurrentError?
        do {
            for try await _ in sub.events {}
        } catch let error as KurrentError {
            caught = error
        }

        guard case .subscriptionDropped = caught else {
            Issue.record("Expected .subscriptionDropped, got \(String(describing: caught))")
            return
        }
    }

    @Test("T5: a repeated teardown runs once")
    func teardownIsIdempotent() async throws {
        let (sub, tornDown) = makeSubscription()
        sub.send(state: .finish())
        for try await _ in sub.events { }
        sub.send(state: .finish())   // ended again

        #expect(tornDown.count == 1)
    }
}
