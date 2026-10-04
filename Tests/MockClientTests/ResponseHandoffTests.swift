//
//  ResponseHandoffTests.swift
//  swift-kurrentdb
//

import Synchronization
import Testing
@testable import KurrentDB

private struct Boom: Error, Equatable {}

/// Counts onTermination calls.
private final class TerminationProbe: Sendable {
    private let calls = Mutex<[String]>([])
    var count: Int { calls.withLock { $0.count } }
    var last: String? { calls.withLock { $0.last } }
    func record(_ error: (any Error)?) { calls.withLock { $0.append(error.map { "\($0)" } ?? "nil") } }
}

@Suite("ResponseHandoff", .timeLimit(.minutes(1)))
struct ResponseHandoffTests {
    /// Yields enough times for spawned tasks to reach their next suspension point.
    private func settle() async {
        for _ in 0 ..< 200 { await Task.yield() }
    }

    @Test("Delivers in order and ends with nil after finish")
    func deliversInOrder() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 2)
        let producer = Task {
            for i in 1 ... 5 { try await handoff.send(i) }
            handoff.finish()
        }
        var received: [Int] = []
        while let value = try await handoff.next() { received.append(value) }
        try await producer.value
        #expect(received == [1, 2, 3, 4, 5])
        #expect(handoff.sentCount == 5)
        #expect(handoff.deliveredCount == 5)
    }

    @Test("finish(throwing:) surfaces the error after the buffer drains, then nil")
    func finishWithError() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 2)
        try await handoff.send(1)
        handoff.finish(throwing: Boom())
        #expect(try await handoff.next() == 1)
        await #expect(throws: Boom.self) { _ = try await handoff.next() }
        #expect(try await handoff.next() == nil)
    }

    @Test("The producer can run at most `capacity` elements ahead")
    func producerSuspendsWhenFull() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 1)
        let producer = Task {
            for i in 1 ... 10 { try await handoff.send(i) }
            handoff.finish()
        }
        await settle()
        #expect(handoff.sentCount == 1)

        #expect(try await handoff.next() == 1)
        await settle()
        #expect(handoff.sentCount == 2)
        #expect(handoff.sentCount - handoff.deliveredCount <= 1)

        handoff.cancel()
        _ = await producer.result
    }

    @Test("cancel() wakes a suspended producer with CancellationError and fires onTermination once")
    func cancelWakesProducer() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        try await handoff.send(1)
        let producer = Task { try await handoff.send(2) }
        await settle()

        handoff.cancel()
        handoff.cancel()
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(try await handoff.next() == nil)
        #expect(probe.count == 1)
        #expect(probe.last == "nil")
    }

    @Test("finish fires onTermination with its error, and a later cancel does not fire again")
    func finishThenCancelFiresOnce() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(onTermination: { probe.record($0) })
        handoff.finish(throwing: Boom())
        handoff.cancel()
        #expect(probe.count == 1)
        #expect(probe.last == "\(Boom())")
    }

    @Test("Dropping an un-iterated stream cancels the hand-off")
    func droppedStreamCancels() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(onTermination: { probe.record($0) })
        do { _ = handoff.makeStream() }
        #expect(probe.count == 1)
        await #expect(throws: CancellationError.self) { try await handoff.send(1) }
    }

    @Test("Breaking out of the loop cancels the hand-off once the stream goes out of scope")
    func breakCancels() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        let producer = Task {
            for i in 1 ... 100 { try await handoff.send(i) }
            handoff.finish()
        }
        func consumeFirst() async throws -> Int? {
            for try await value in handoff.makeStream() { return value }
            return nil
        }
        #expect(try await consumeFirst() == 1)
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(probe.count == 1)
    }

    @Test("Cancelling the consumer task cancels the hand-off")
    func consumerTaskCancellation() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        let consumer = Task {
            var count = 0
            for try await _ in handoff.makeStream() { count += 1 }
            return count
        }
        await settle()
        consumer.cancel()
        let outcome = await consumer.result
        #expect(try outcome.get() == 0)
        #expect(probe.count == 1)
        await #expect(throws: CancellationError.self) { try await handoff.send(1) }
    }

    @Test("makeStream(_:) skips elements the transform maps to nil")
    func transformSkips() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 4)
        for i in 1 ... 4 { try await handoff.send(i) }
        handoff.finish()
        let evens = handoff.makeStream { $0 % 2 == 0 ? $0 : nil }
        var received: [Int] = []
        for try await value in evens { received.append(value) }
        #expect(received == [2, 4])
    }

    @Test("Cancelling the producer task surfaces CancellationError to the consumer after the buffer drains")
    func producerCancellationIsNotACleanEnd() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        try await handoff.send(1)
        let producer = Task { try await handoff.send(2) }
        await settle()

        producer.cancel()
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(try await handoff.next() == 1)
        await #expect(throws: CancellationError.self) { _ = try await handoff.next() }
        #expect(try await handoff.next() == nil)
        #expect(probe.count == 1)
        #expect(probe.last != "nil")
    }

    @Test("finish() wakes a suspended producer with CancellationError")
    func finishReleasesPendingProducer() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 1)
        try await handoff.send(1)
        let producer = Task { try await handoff.send(2) }
        await settle()

        handoff.finish()
        handoff.cancel()
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(handoff.sentCount == 1)
        #expect(try await handoff.next() == 1)
        #expect(try await handoff.next() == nil)
    }

    @Test("A consumer suspended in next() receives the error from finish(throwing:), then nil")
    func waitingConsumerReceivesFinishError() async throws {
        let handoff = ResponseHandoff<Int>()
        let consumer = Task { try await handoff.next() }
        await settle()

        handoff.finish(throwing: Boom())
        await #expect(throws: Boom.self) { _ = try await consumer.value }
        #expect(try await handoff.next() == nil)
    }
}
