//
//  DefaultDeadlinePathTests.swift
//  swift-kurrentdb
//
//  No server needed. Every call targets a SilentListener, which never answers, so a call ends
//  only through its deadline or its caller's cancellation. That makes "the default deadline is
//  applied" and "cancellation is reported as connectionClosed" independent of machine speed.
//

import GRPCCore
import Testing
@testable import KurrentDB

@Suite("Default deadline on completing calls", .serialized, .timeLimit(.minutes(1)))
struct DefaultDeadlinePathTests {
    private func makeNode(port: Int, defaultDeadline: Int, supporting descriptors: [GRPCCore.MethodDescriptor]) -> Node {
        let settings = ClientSettings.localhost().defaultDeadline(defaultDeadline)
        let info = ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        return Node(endpoint: Endpoint(host: "127.0.0.1", port: UInt32(port)), settings: settings, serverInfo: info, connections: provider)
    }

    private func isDeadlineExceeded(_ error: any Error) -> Bool {
        if case .deadlineExceeded = error as? KurrentError { return true }
        return false
    }

    @Test("A unary call ends with deadlineExceeded at the default deadline")
    func unary() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Delete(to: .init(name: "any"), options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("A client-streaming append ends with deadlineExceeded at the default deadline")
    func clientStreaming() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Append(to: .init(name: "any"), events: [EventData(eventType: "T", model: ["k": "v"])], options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("A buffered read ends with deadlineExceeded at the default deadline")
    func bufferedRead() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("A batch append ends with deadlineExceeded at the default deadline")
    func batchAppend() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let record = try EventRecord(eventType: "T", payload: .json(["k": "v"]))
        let usecase = Streams<MultiStreamsTarget>.BatchAppend(streamEvents: [StreamEvent(stream: "any", records: [record])])
        let node = makeNode(port: listener.port, defaultDeadline: 300, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect { _ = try await usecase.perform(node: node, callOptions: .defaults) } throws: { isDeadlineExceeded($0) }
    }

    @Test("An explicit CallOptions.timeout wins over the default deadline")
    func explicitTimeoutWins() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Delete(to: .init(name: "any"), options: .init())
        // The default deadline alone would let this call wait an hour.
        let node = makeNode(port: listener.port, defaultDeadline: 3_600_000, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }
        var options = CallOptions.defaults
        options.timeout = .milliseconds(300)

        await #expect { _ = try await usecase.perform(node: node, callOptions: options) } throws: { isDeadlineExceeded($0) }
    }

    @Test("Cancelling the caller of a buffered read reports connectionClosed, not an internal error")
    func bufferedReadCallerCancellation() async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(port: listener.port, defaultDeadline: .max, supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        let reader = Task { try await usecase.perform(node: node, callOptions: .defaults) }
        try await Task.sleep(for: .milliseconds(300))
        reader.cancel()
        let outcome = await reader.result
        #expect { _ = try outcome.get() } throws: { error in
            if case .connectionClosed = error as? KurrentError { return true }
            return false
        }
    }
}

// MARK: - Establishing a lazy read (§5.1.3, S2, S6)

private typealias ReadCall = Streams<SpecifiedStream>.ReadCall

/// The delivery path a lazy read is driven on: `next(isolation:)` off any actor takes the direct
/// path, on the main actor the hand-off path.
enum EstablishmentPath: String, CaseIterable, Sendable, CustomTestStringConvertible {
    case direct, handoff
    var testDescription: String { rawValue }
}

/// What draining a read gave, and how long it took.
private struct Drained: Sendable {
    var count = 0
    var error: (any Error)?
    var elapsed: Duration = .zero
}

private func drain(_ call: ReadCall, on path: EstablishmentPath) async -> Drained {
    switch path {
    case .direct: await drainNonisolated(call)
    case .handoff: await drainOnMainActor(call)
    }
}

private func drainNonisolated(_ call: ReadCall) async -> Drained {
    let start = ContinuousClock.now
    let iterator = call.makeAsyncIterator()
    var drained = Drained()
    do {
        while try await iterator.next(isolation: nil) != nil { drained.count += 1 }
    } catch {
        drained.error = error
    }
    drained.elapsed = ContinuousClock.now - start
    return drained
}

@MainActor
private func drainOnMainActor(_ call: ReadCall) async -> Drained {
    let start = ContinuousClock.now
    let iterator = call.makeAsyncIterator()
    var drained = Drained()
    do {
        while try await iterator.next(isolation: MainActor.shared) != nil { drained.count += 1 }
    } catch {
        drained.error = error
    }
    drained.elapsed = ContinuousClock.now - start
    return drained
}

@Suite("Default deadline on establishing a lazy read", .serialized, .timeLimit(.minutes(1)))
struct LazyReadEstablishmentDeadlineTests {
    private static let refused = Endpoint(host: "127.0.0.1", port: 1)
    private static let descriptor = Streams<SpecifiedStream>.Read(from: .init(name: "orders"), options: .init()).methodDescriptor

    /// Room above a budget for the cancellation to take effect: the budget is a bound only if
    /// cancelling a queued or connecting RPC is prompt.
    private static let slack: Duration = .milliseconds(200)

    private func isDeadlineExceeded(_ error: (any Error)?) -> Bool {
        if case .deadlineExceeded = error as? KurrentError { return true }
        return false
    }

    private func eventually(timeout: Duration = .seconds(10), _ condition: () async -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if await condition() { return true }
            try await Task.sleep(for: .milliseconds(5))
        }
        return await condition()
    }

    /// A selector whose cached node is `endpoint`, seeded with server info "test" (discovery would
    /// replace it with what the server reports).
    private func makeCachedSelector(endpoint: Endpoint, defaultDeadline: Int, maxAttempts: Int = 2) async -> NodeSelector {
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = maxAttempts
        policy.initialDelay = .zero
        let settings = ClientSettings(clusterMode: .standalone(endpoint: endpoint))
            .defaultDeadline(defaultDeadline)
            .operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        let info = ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: [ServerFeatures.SupportedMethod(methodName: Self.descriptor.method, serviceName: Self.descriptor.service.fullyQualifiedService, features: [])]
        )
        await selector.cacheNodeForTesting(Node(endpoint: endpoint, settings: settings, serverInfo: info, connections: selector.connections))
        return selector
    }

    /// The seeded node is still cached: nothing invalidated it.
    private func seededNodeIsCached(_ selector: NodeSelector, endpoint: Endpoint) async -> Bool {
        let node = await selector.cachedNodeForTesting
        return node?.endpoint == endpoint && node?.serverInfo.serverVersion == "test"
    }

    @Test("A lazy read's establishment ends with deadlineExceeded when discovery outlasts the default deadline", arguments: EstablishmentPath.allCases)
    func discoveryOutlastsTheBudget(_ path: EstablishmentPath) async throws {
        // No cached node: discovery against the refused port retries for about a second.
        let settings = ClientSettings(clusterMode: .standalone(endpoint: Self.refused)).defaultDeadline(300)
        let selector = NodeSelector(settings: settings)
        defer { selector.connections.shutdown() }
        let call: ReadCall = Streams<SpecifiedStream>(target: .specified("orders"), selector: selector, callOptions: .defaults).read()

        let drained = await drain(call, on: path)

        #expect(isDeadlineExceeded(drained.error), "\(String(describing: drained.error))")
        #expect(drained.elapsed <= .milliseconds(300) + Self.slack, "\(drained.elapsed)")
        #expect(selector.connections.createdReadConnectionCount == 0)
        #expect(selector.connections.shutdownHandlerCount == 0)
    }

    @Test("A lazy read's establishment ends with deadlineExceeded when the server never accepts, without resetting the cached node", arguments: EstablishmentPath.allCases)
    func serverNeverAccepts(_ path: EstablishmentPath) async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let endpoint = Endpoint(host: "127.0.0.1", port: UInt32(listener.port))
        let selector = await makeCachedSelector(endpoint: endpoint, defaultDeadline: 300, maxAttempts: 3)
        defer { selector.connections.shutdown() }
        let call: ReadCall = Streams<SpecifiedStream>(target: .specified("orders"), selector: selector, callOptions: .defaults).read()

        let drained = await drain(call, on: path)

        #expect(isDeadlineExceeded(drained.error), "\(String(describing: drained.error))")
        #expect(drained.elapsed <= .milliseconds(300) + Self.slack, "\(drained.elapsed)")
        #expect(await seededNodeIsCached(selector, endpoint: endpoint))
        #expect(selector.connections.createdReadConnectionCount == 1)
        #expect(try await eventually { selector.connections.readEntrySnapshot(for: endpoint)?.retainCount == 0 })
        #expect(selector.connections.shutdownHandlerCount == 0)
    }

    @Test("A caller-set CallOptions.timeout expiring before acceptance is not retried and does not reset the node", arguments: EstablishmentPath.allCases)
    func callTimeoutBeforeAcceptance(_ path: EstablishmentPath) async throws {
        let listener = try await SilentListener.start()
        defer { Task { await listener.stop() } }
        let endpoint = Endpoint(host: "127.0.0.1", port: UInt32(listener.port))
        let selector = await makeCachedSelector(endpoint: endpoint, defaultDeadline: .max, maxAttempts: 3)
        defer { selector.connections.shutdown() }
        var options = CallOptions.defaults
        options.timeout = .milliseconds(200)
        let call: ReadCall = Streams<SpecifiedStream>(target: .specified("orders"), selector: selector, callOptions: options).read()

        let drained = await drain(call, on: path)

        #expect(isDeadlineExceeded(drained.error), "\(String(describing: drained.error))")
        #expect(drained.elapsed <= .milliseconds(200) + Self.slack, "\(drained.elapsed)")
        #expect(await seededNodeIsCached(selector, endpoint: endpoint))
        #expect(selector.connections.createdReadConnectionCount == 1)
        #expect(try await eventually { selector.connections.readEntrySnapshot(for: endpoint)?.retainCount == 0 })
        #expect(selector.connections.shutdownHandlerCount == 0)
    }

    /// What ends the wait in the fake rows: the caller's call timeout or the client's default deadline.
    enum Bound: String, CaseIterable, Sendable, CustomTestStringConvertible {
        case callTimeout, defaultDeadline
        var testDescription: String { rawValue }
    }

    /// The streams of `client`, bounded by `bound` at 150 ms.
    private func boundedStreams(_ client: KurrentDBClient, fake: InProcessKurrentDB, _ bound: Bound) -> (Streams<SpecifiedStream>, KurrentDBClient?) {
        switch bound {
        case .callTimeout:
            var options = CallOptions.defaults
            options.timeout = .milliseconds(150)
            return (Streams(target: .specified("orders"), selector: client.selector, callOptions: options), nil)
        case .defaultDeadline:
            // A second client with its own selector: the budget is read from the selector's settings.
            let bounded = KurrentDBClient(settings: fake.settings.defaultDeadline(150))
            return (bounded.streams(specified: "orders"), bounded)
        }
    }

    @Test("A server that accepts later than the bound: deadlineExceeded, one read, one read connection, the node kept",
          arguments: EstablishmentPath.allCases, Bound.allCases)
    func acceptanceOutlastsTheBound(_ path: EstablishmentPath, _ bound: Bound) async throws {
        var script = InProcessKurrentDB.ReadScript.events(3)
        script.acceptDelay = .milliseconds(400)
        let fake = InProcessKurrentDB(read: script)
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let (streams, other) = boundedStreams(client, fake: fake, bound)
        defer { try? other?.shutdown() }
        let selector = other?.selector ?? client.selector
        _ = try await selector.select()   // discovered before the read, so the count below is the read's
        let discoveries = fake.discoveries

        let drained = await drain(streams.read(), on: path)

        #expect(isDeadlineExceeded(drained.error), "\(String(describing: drained.error))")
        #expect(drained.count == 0)
        #expect(drained.elapsed <= .milliseconds(150) + Self.slack, "\(drained.elapsed)")
        #expect(fake.readsStarted == 1)
        #expect(fake.discoveries == discoveries, "the node was invalidated and discovered again")
        #expect(await selector.cachedNodeForTesting != nil)
        #expect(selector.connections.createdReadConnectionCount == 1)
        #expect(selector.connections.shutdownHandlerCount == 0)
        #expect(try await eventually { selector.connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0 })
        #expect(try await eventually { fake.openStreams == 0 })
    }

    @Test("A read waiting for a stream slot on a full read connection longer than the bound: deadlineExceeded, the node kept",
          arguments: EstablishmentPath.allCases, Bound.allCases)
    func slotWaitOutlastsTheBound(_ path: EstablishmentPath, _ bound: Bound) async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold), maxConcurrentStreams: 1)
        let client = KurrentDBClient(settings: fake.settings)
        defer { try? client.shutdown() }
        let (streams, other) = boundedStreams(client, fake: fake, bound)
        defer { try? other?.shutdown() }
        let selector = other?.selector ?? client.selector
        // The held read takes the only slot of the read connection the bounded read then uses.
        let holder = other ?? client
        var held: Streams<SpecifiedStream>.ReadCall.Iterator? = holder.streams(specified: "orders").read().makeAsyncIterator()
        _ = try await held?.next()
        #expect(fake.openStreams == 1)
        _ = try await selector.select()
        let discoveries = fake.discoveries

        let drained = await drain(streams.read(), on: path)

        #expect(isDeadlineExceeded(drained.error), "\(String(describing: drained.error))")
        #expect(drained.elapsed <= .milliseconds(150) + Self.slack, "\(drained.elapsed)")
        #expect(fake.readsStarted == 1)   // the held read; the bounded one never got a slot
        #expect(fake.discoveries == discoveries, "the node was invalidated and discovered again")
        #expect(await selector.cachedNodeForTesting != nil)
        #expect(selector.connections.createdReadConnectionCount == 1)
        #expect(selector.connections.shutdownHandlerCount == 1)   // the held read's
        #expect(try await eventually { fake.openStreams == 1 })
        held = nil
        #expect(try await eventually { fake.openStreams == 0 })
        #expect(try await eventually { selector.connections.shutdownHandlerCount == 0 })
    }

    @Test("A budget the open beats leaves the read untouched", arguments: EstablishmentPath.allCases)
    func budgetBeaten(_ path: EstablishmentPath) async throws {
        let fake = InProcessKurrentDB(read: .events(3))
        let client = KurrentDBClient(settings: fake.settings.defaultDeadline(5_000))
        defer { try? client.shutdown() }

        let drained = await drain(client.streams(specified: "orders").read(), on: path)

        #expect(drained.error == nil, "\(String(describing: drained.error))")
        #expect(drained.count == 3)
        #expect(fake.readsStarted == 1)
    }

    @Test("The timer and the open racing: the outcome is either the events or deadlineExceeded, never a leaked call", arguments: EstablishmentPath.allCases)
    func timerRacesTheOpen(_ path: EstablishmentPath) async throws {
        var script = InProcessKurrentDB.ReadScript.events(3)
        script.acceptDelay = .milliseconds(100)
        let fake = InProcessKurrentDB(read: script)

        // Budgets swept across the accept time, so the timer fires just before, at or just after
        // the server's response; one client per run, discovered and with its read connection warm.
        for run in 0 ..< 20 {
            let budget = 96 + (run % 5) * 3   // 96 … 108 ms
            let client = KurrentDBClient(settings: fake.settings.defaultDeadline(budget))
            defer { try? client.shutdown() }
            let connections = client.selector.connections
            _ = try await client.selector.select()
            _ = try? connections.acquire(fake.endpoint, purpose: .read).release()

            let drained = await drain(client.streams(specified: "orders").read(), on: path)
            let opened = drained.error == nil && drained.count == 3
            let expired = isDeadlineExceeded(drained.error) && drained.count == 0
            #expect(opened || expired, "run \(run): \(drained.count) events, \(String(describing: drained.error))")
            #expect(try await eventually { connections.readEntrySnapshot(for: fake.endpoint)?.retainCount == 0 }, "run \(run)")
            #expect(try await eventually { fake.openStreams == 0 }, "run \(run)")
            #expect(connections.shutdownHandlerCount == 0, "run \(run)")
            #expect(connections.createdReadConnectionCount == 1, "run \(run)")
        }
    }

    @Test("A buffered read whose deadline expires mid-drain is still retried per attempt, as in 2.x")
    func bufferedDeadlineIsPerAttempt() async throws {
        let fake = InProcessKurrentDB(read: .events(3, then: .hold))
        let client = KurrentDBClient(settings: fake.settings.defaultDeadline(150))
        defer { try? client.shutdown() }

        await #expect(throws: KurrentError.deadlineExceeded) {
            for try await _ in try await client.streams(specified: "orders").read().buffered {}
        }
        // The default policy's two attempts, each with its own deadline (S2 "per attempt").
        #expect(fake.readsStarted == 2)
    }
}
