//
//  ReadDeliveryPathTests.swift
//  swift-kurrentdb
//
//  No server needed: the fake node of InProcessKurrentDB.swift, or a refused port. A lazy read takes
//  the direct path (the RPC handler parks while the consumer iterates grpc-swift's sequence) when its
//  first next(isolation:) runs off any actor, and the hand-off path when it runs on one. Every row
//  of the matrix runs in all three contexts and expects the same outcome from both paths.
//

import Foundation
import GRPCCore
import Synchronization
import Testing
@testable import KurrentDB

private typealias ReadCall = Streams<SpecifiedStream>.ReadCall
private typealias DeliveryPath = ReadCall.Iterator.DeliveryPath

/// Where a test iterates a read.
enum IterationContext: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case nonisolated, mainActor, customActor

    var testDescription: String { rawValue }

    fileprivate var expectedPath: DeliveryPath {
        self == .nonisolated ? .direct : .handoff
    }
}

/// What iterating a read gave: how many elements, the error it ended with, the path it took.
private struct Outcome: Sendable {
    var count = 0
    var error: (any Error)?
    var path: DeliveryPath?
}

/// How a test iterates: a pause per element, a `break` after some elements, and a hook that runs
/// in the loop body with the running count.
private struct Iteration: Sendable {
    var perElement: Duration?
    var breakAfter: Int?
    var onElement: (@Sendable (Int) -> Void)?
}

/// Iterates a read in the given context and reports what happened. Each context runs the same
/// loop; only the isolation `next(isolation:)` sees differs (as `for try await` would pass it).
private func drive(_ call: ReadCall, in context: IterationContext, _ iteration: Iteration = Iteration()) async -> Outcome {
    switch context {
    case .nonisolated: await driveNonisolated(call, iteration)
    case .mainActor: await driveOnMainActor(call, iteration)
    case .customActor: await Driver().drive(call, iteration)
    }
}

private func driveNonisolated(_ call: ReadCall, _ iteration: Iteration) async -> Outcome {
    let iterator = call.makeAsyncIterator()
    var outcome = Outcome()
    do {
        while try await iterator.next(isolation: nil) != nil {
            outcome.count += 1
            iteration.onElement?(outcome.count)
            if outcome.count == iteration.breakAfter { break }
            if let pause = iteration.perElement { try await Task.sleep(for: pause) }
        }
    } catch {
        outcome.error = error
    }
    outcome.path = iterator.deliveryPath
    return outcome
}

@MainActor
private func driveOnMainActor(_ call: ReadCall, _ iteration: Iteration) async -> Outcome {
    let iterator = call.makeAsyncIterator()
    var outcome = Outcome()
    do {
        while try await iterator.next(isolation: MainActor.shared) != nil {
            outcome.count += 1
            iteration.onElement?(outcome.count)
            if outcome.count == iteration.breakAfter { break }
            if let pause = iteration.perElement { try await Task.sleep(for: pause) }
        }
    } catch {
        outcome.error = error
    }
    outcome.path = iterator.deliveryPath
    return outcome
}

/// A custom actor (not the main actor), the case Review Focus 1 names.
private actor Driver {
    func drive(_ call: ReadCall, _ iteration: Iteration) async -> Outcome {
        let iterator = call.makeAsyncIterator()
        var outcome = Outcome()
        do {
            while try await iterator.next(isolation: self) != nil {
                outcome.count += 1
                iteration.onElement?(outcome.count)
                if outcome.count == iteration.breakAfter { break }
                if let pause = iteration.perElement { try await Task.sleep(for: pause) }
            }
        } catch {
            outcome.error = error
        }
        outcome.path = iterator.deliveryPath
        return outcome
    }
}

@Suite("Read delivery paths", .serialized, .timeLimit(.minutes(2)))
struct ReadDeliveryPathTests {
    private static let refused = Endpoint(host: "127.0.0.1", port: 1)

    /// Waits until the condition holds or the timeout passes: after `break` or a cancellation the
    /// lease and the shutdown handler are given back in the background.
    private func eventually(timeout: Duration = .seconds(10), poll: Duration = .milliseconds(5), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: poll)
        }
        return condition()
    }

    private func isKurrentError(_ error: (any Error)?, _ expected: KurrentError) -> Bool {
        (error as? KurrentError) == expected
    }

    // MARK: path selection

    @Test("next(isolation:) picks the direct path off any actor and the hand-off path on one")
    func pathSelection() async throws {
        let fake = InProcessKurrentDB(read: .events(1))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "orders")

        let offActor = try await Task.detached { () -> DeliveryPath? in
            let iterator = stream.read().makeAsyncIterator()
            #expect(iterator.deliveryPath == nil)   // nothing is chosen before the first next()
            _ = try await iterator.next()
            return iterator.deliveryPath
        }.value
        #expect(offActor == .direct)

        let onActor = try await Self.advanceOnMain(stream.read())
        #expect(onActor == .handoff)

        // `for try await` passes #isolation: a plain async function takes the direct path.
        var count = 0
        for try await _ in stream.read() { count += 1 }
        #expect(count == 1)
    }

    @MainActor
    private static func advanceOnMain(_ call: ReadCall) async throws -> DeliveryPath? {
        let iterator = call.makeAsyncIterator()
        _ = try await iterator.next(isolation: MainActor.shared)
        return iterator.deliveryPath
    }

    @Test("The path chosen on the first next(isolation:) is kept when the iterator is advanced elsewhere later")
    func pathIsKept() async throws {
        let fake = InProcessKurrentDB(read: .events(3))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let iterator = client.streams(specified: "orders").read().makeAsyncIterator()
        #expect(try await iterator.next(isolation: nil) != nil)
        #expect(iterator.deliveryPath == .direct)
        let (rest, path) = await Self.drainOnMain(iterator)
        #expect(rest == 2)
        #expect(path == .direct)
    }

    @MainActor
    private static func drainOnMain(_ iterator: sending ReadCall.Iterator) async -> (Int, DeliveryPath?) {
        var count = 0
        while (try? await iterator.next(isolation: MainActor.shared)) ?? nil != nil { count += 1 }
        return (count, iterator.deliveryPath)
    }

    // MARK: the matrix (both paths, three contexts)

    @Test("A refused connection throws KurrentError at the first next() and returns the read connection's lease", arguments: IterationContext.allCases)
    func establishmentRefused(_ context: IterationContext) async throws {
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        let settings = ClientSettings(clusterMode: .standalone(endpoint: Self.refused)).operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        defer { selector.connections.shutdown() }
        let descriptor = Streams<SpecifiedStream>.Read(from: .init(name: "orders"), options: .init()).methodDescriptor
        let info = ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: [ServerFeatures.SupportedMethod(methodName: descriptor.method, serviceName: descriptor.service.fullyQualifiedService, features: [])]
        )
        await selector.cacheNodeForTesting(Node(endpoint: Self.refused, settings: settings, serverInfo: info, connections: selector.connections))
        var callOptions = CallOptions.defaults
        callOptions.timeout = .seconds(2)
        let call: ReadCall = Streams<SpecifiedStream>(target: .specified("orders"), selector: selector, callOptions: callOptions).read()

        let outcome = await drive(call, in: context)

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.count == 0)
        #expect(outcome.error is KurrentError, "\(String(describing: outcome.error))")
        #expect(selector.connections.createdReadConnectionCount == 1)
        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.readEntrySnapshot(for: Self.refused)?.retainCount == 0)
        #expect(selector.connections.shutdownHandlerCount == 0)
    }

    @Test("A call deadline expiring with messages still buffered ends the read at the next element with deadlineExceeded", arguments: IterationContext.allCases)
    func deadlineMidStreamWithBufferedMessages(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(1000, then: .hold))
        var options = CallOptions.defaults
        options.timeout = .milliseconds(300)
        let client = KurrentDBClient(settings: fake.settings, defaultCallOptions: options)
        defer { client.shutdown() }
        let connections = client.selector.connections

        let outcome = await drive(client.streams(specified: "orders").read(), in: context, Iteration(perElement: .milliseconds(2)))

        #expect(outcome.path == context.expectedPath)
        #expect(isKurrentError(outcome.error, .deadlineExceeded), "\(String(describing: outcome.error))")
        // At 2 ms per element the deadline ends the read well before the end: the direct path checks
        // the RPC's terminal error per element instead of draining what had already arrived.
        #expect(outcome.count > 0 && outcome.count < 1000, "\(outcome.count) elements")
        #expect(fake.readsStarted == 1)
        #expect(connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0)
        #expect(connections.shutdownHandlerCount == 0)
    }

    @Test("Cancelling the iterating task ends the read with CancellationError and returns the lease", arguments: IterationContext.allCases)
    func callerCancellation(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(1000, then: .hold))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let connections = client.selector.connections
        let call: ReadCall = client.streams(specified: "orders").read()

        let reader = Task { await drive(call, in: context, Iteration(perElement: .milliseconds(2))) }
        try await Task.sleep(for: .milliseconds(100))
        reader.cancel()
        let outcome = await reader.value

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.error is CancellationError, "\(String(describing: outcome.error))")
        #expect(outcome.count > 0 && outcome.count < 1000, "\(outcome.count) elements")
        #expect(try await eventually { connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0 })
        #expect(try await eventually { connections.shutdownHandlerCount == 0 })
    }

    @Test("break after the first element, 150 times: no lease, stream slot or shutdown handler leaks", arguments: IterationContext.allCases)
    func breakAfterFirst(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(50))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let connections = client.selector.connections
        let stream = client.streams(specified: "orders")

        for run in 0 ..< 150 {
            let outcome = await drive(stream.read(), in: context, Iteration(breakAfter: 1))
            #expect(outcome.path == context.expectedPath)
            #expect(outcome.count == 1, "run \(run)")
            #expect(outcome.error == nil, "run \(run): \(String(describing: outcome.error))")
            // The lease goes back only after the RPC task has ended, which is after the transport
            // closed the stream: a lease returned earlier would show here as a stream still open.
            #expect(try await eventually { connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0 }, "run \(run)")
            #expect(fake.openStreams == 0, "run \(run): the lease was returned while the RPC stream was still open")
        }
        #expect(connections.createdReadConnectionCount == 1)
        #expect(try await eventually { connections.shutdownHandlerCount == 0 })
        #expect(try await eventually { fake.openStreams == 0 })
        #expect(fake.readsStarted == 150)
    }

    @Test("shutdown() during iteration ends the read with exactly connectionClosed", arguments: IterationContext.allCases)
    func shutdownDuringIteration(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let connections = client.selector.connections
        let shutter = TaskSlot()

        let outcome = await drive(client.streams(specified: "orders").read(), in: context, Iteration(onElement: { count in
            guard count == 3 else { return }
            #expect(connections.shutdownHandlerCount == 1)
            // From another task, once the consumer is suspended in next() waiting for a fourth element.
            shutter.task.withLock { $0 = Task { try? await Task.sleep(for: .milliseconds(100)); connections.shutdown() } }
        }))
        await shutter.task.withLock { $0 }?.value

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.count == 3)
        #expect(isKurrentError(outcome.error, .connectionClosed), "\(String(describing: outcome.error))")
        #expect(connections.shutdownHandlerCount == 0)
        #expect(connections.readEntrySnapshot(for: fake.endpoint)?.retainCount ?? 0 == 0)
    }

    @Test("A deadline that ended the RPC before shutdown() stays the read's error: the first terminal error wins", arguments: IterationContext.allCases)
    func deadlineThenShutdown(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        var options = CallOptions.defaults
        options.timeout = .milliseconds(100)
        let client = KurrentDBClient(settings: fake.settings, defaultCallOptions: options)
        defer { client.shutdown() }
        let connections = client.selector.connections

        let outcome = await drive(client.streams(specified: "orders").read(), in: context, Iteration(onElement: { count in
            guard count == 1 else { return }
            // In the loop body, so no next() runs meanwhile: the deadline ends the RPC first, then
            // shutdown() runs the read's handler while two events are still buffered.
            Thread.sleep(forTimeInterval: 0.4)
            connections.shutdown()
        }))

        #expect(outcome.path == context.expectedPath)
        #expect(isKurrentError(outcome.error, .deadlineExceeded), "\(String(describing: outcome.error))")
        #expect(outcome.count < 3)
        #expect(connections.shutdownHandlerCount == 0)
    }

    @Test("shutdown() before the first next() ends the read with connectionClosed and opens nothing", arguments: IterationContext.allCases)
    func shutdownBeforeFirstNext(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(3))
        let client = KurrentDBClient(settings: fake.settings)
        let connections = client.selector.connections
        let call: ReadCall = client.streams(specified: "orders").read()
        client.shutdown()

        let outcome = await drive(call, in: context)

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.count == 0)
        #expect(isKurrentError(outcome.error, .connectionClosed), "\(String(describing: outcome.error))")
        #expect(fake.readsStarted == 0)
        #expect(connections.createdReadConnectionCount == 0)
        #expect(connections.shutdownHandlerCount == 0)
    }

    @Test("A stream the server ends delivers every event, then nil, with the lease and the stream returned", arguments: IterationContext.allCases)
    func serverEnd(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(5))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let connections = client.selector.connections

        let outcome = await drive(client.streams(specified: "orders").read(), in: context)

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.count == 5)
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        // Returned before the last next() returned nil, not in the background.
        #expect(connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0)
        #expect(connections.shutdownHandlerCount == 0)
        #expect(fake.openStreams == 0)
    }

    @Test("A stream with zero events ends cleanly on the first next()", arguments: IterationContext.allCases)
    func emptyStream(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(0))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let connections = client.selector.connections

        let outcome = await drive(client.streams(specified: "orders").read(), in: context)

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.count == 0)
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(fake.readsStarted == 1)
        #expect(connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0)
        #expect(connections.shutdownHandlerCount == 0)
        #expect(fake.openStreams == 0)
    }

    @Test("A server error after two events ends the read with KurrentError.serverError", arguments: IterationContext.allCases)
    func serverEndWithLateError(_ context: IterationContext) async throws {
        let fake = InProcessKurrentDB(read: .events(2, then: .error(RPCError(code: .internalError, message: "boom"))))
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let connections = client.selector.connections

        let outcome = await drive(client.streams(specified: "orders").read(), in: context)

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.count == 2)
        #expect(isKurrentError(outcome.error, .serverError("boom")), "\(String(describing: outcome.error))")
        #expect(fake.readsStarted == 1)   // after acceptance: never retried
        #expect(connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0)
        #expect(connections.shutdownHandlerCount == 0)
    }

    @Test("A position frame before the events is skipped on both paths (S12)", arguments: IterationContext.allCases)
    func positionFrameSkipped(_ context: IterationContext) async throws {
        var script = InProcessKurrentDB.ReadScript.events(2)
        var frame = Streams<SpecifiedStream>.Read.UnderlyingResponse()
        frame.content = .lastStreamPosition(1)
        script.messages.insert(frame, at: 0)
        let fake = InProcessKurrentDB(read: script)
        let client = KurrentDBClient(settings: fake.settings)
        defer { client.shutdown() }
        let connections = client.selector.connections

        let outcome = await drive(client.streams(specified: "orders").read { $0.compatibility = 1 }, in: context)

        #expect(outcome.path == context.expectedPath)
        #expect(outcome.count == 2)
        #expect(outcome.error == nil, "\(String(describing: outcome.error))")
        #expect(connections.shutdownHandlerCount == 0)
    }
}

/// A task one closure starts and the test then awaits.
private final class TaskSlot: Sendable {
    let task = Mutex<Task<Void, Never>?>(nil)
}
