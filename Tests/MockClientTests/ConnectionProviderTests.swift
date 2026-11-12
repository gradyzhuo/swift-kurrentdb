//
//  ConnectionProviderTests.swift
//  swift-kurrentdb
//
// No server needed: everything points at privileged ports nothing listens on (127.0.0.1:1 and :2), so a
// connection is refused at once (ECONNREFUSED). TEST-NET addresses (192.0.2.x) are avoided on purpose: they
// do not answer a SYN, so a runConnections() that has started connecting reacts to a cancel only when the TCP
// connect times out (about 10 seconds), which would make "the runTask ends after a cancel" depend on timing.
// These tests still make real connection attempts (no server is involved, but there is network activity).
//
// The sweeper is always off (sweepInterval: nil) and sweep(now:) is driven with injected instants,
// so the reclaiming assertions do not depend on real time. Every test ends with shutdown(), so the test
// process does not collect runConnections() calls hanging on unreachable targets.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOPosix
import Synchronization
import Testing
@testable import KurrentDB

@Suite("ConnectionProvider", .serialized, .timeLimit(.minutes(1)))
struct ConnectionProviderTests {
    private static let endpointA = Endpoint(host: "127.0.0.1", port: 1)
    private static let endpointB = Endpoint(host: "127.0.0.1", port: 2)

    private func makeProvider(idleTimeout: Duration = .seconds(3600)) -> ConnectionProvider {
        ConnectionProvider(settings: .localhost(), idleTimeout: idleTimeout, sweepInterval: nil)
    }

    /// Waits until the condition holds or the time runs out. Only for waiting on a real task to finish (when a
    /// runTask ends after a cancel depends on scheduling), never for a time-related assertion about behaviour.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0 ..< 200 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - Event-loop group

    @Test("The provider keeps the injected event-loop group and hands it to every Posix transport it builds")
    func injectedGroupReachesTheProvider() {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        defer { try? group.syncShutdownGracefully() }
        let provider = ConnectionProvider(settings: .localhost(), eventLoopGroup: group, idleTimeout: .seconds(1), sweepInterval: nil)
        defer { provider.shutdown() }
        #expect(provider.eventLoopGroup === group)
        let client = KurrentDBClient(settings: .localhost(), eventLoopGroup: group)
        defer { client.shutdown() }
        #expect(client.eventLoopGroup === group)
        #expect(client.selector.connections.eventLoopGroup === group)
    }

    @Test("Without an injected group the client runs on NIO's process-wide singleton")
    func defaultGroupIsTheSingleton() {
        let client = KurrentDBClient(settings: .localhost())
        defer { client.shutdown() }
        #expect(client.selector.connections.eventLoopGroup === MultiThreadedEventLoopGroup.singleton)
    }

    // MARK: - Shared: reuse

    @Test("Acquiring the same endpoint twice returns the same connection")
    func reusesConnectionForSameEndpoint() throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let first = try provider.acquire(Self.endpointA)
        let second = try provider.acquire(Self.endpointA)
        defer { first.release(); second.release() }

        #expect(first.client === second.client)
        #expect(provider.createdSharedConnectionCount == 1)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 2)
    }

    @Test("Different endpoints get a connection each")
    func separateConnectionsPerEndpoint() throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let a = try provider.acquire(Self.endpointA)
        let b = try provider.acquire(Self.endpointB)
        defer { a.release(); b.release() }

        #expect(a.client !== b.client)
        #expect(provider.createdSharedConnectionCount == 2)
    }

    /// The central claim of the change: under high concurrency one endpoint gets one shared connection.
    /// Concurrent misses each build outside the lock, but only one publishes; the others drop their own.
    @Test("100 concurrent acquires of one endpoint create one connection")
    func concurrentAcquiresCreateOneConnection() async throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let ids = try await withThrowingTaskGroup(of: ObjectIdentifier.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    let lease = try provider.acquire(Self.endpointA)
                    defer { lease.release() }
                    return ObjectIdentifier(lease.client)
                }
            }
            var seen: Set<ObjectIdentifier> = []
            for try await id in group {
                seen.insert(id)
            }
            return seen
        }

        #expect(ids.count == 1)
        #expect(provider.createdSharedConnectionCount == 1)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 0)
    }

    // MARK: - Shared: lease accounting

    @Test("release takes effect once; the deinit fallback releases once")
    func releaseIsExactlyOnce() throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let kept = try provider.acquire(Self.endpointA)
        defer { kept.release() }

        let lease = try provider.acquire(Self.endpointA)
        lease.release()
        lease.release()
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 1)

        do {
            _ = try provider.acquire(Self.endpointA)   // released at once → the deinit fallback
        }
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 1)
    }

    /// P1 of the third Codex round: after A is removed, B replaces it on the same endpoint; A's late release must not touch B.
    @Test("A release from an older generation does not affect the entry that replaced it")
    func staleReleaseDoesNotTouchReplacement() async throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let leaseA = try provider.acquire(Self.endpointA)
        let generationA = try #require(provider.sharedEntrySnapshot(for: Self.endpointA)).generation

        // Take the real "runTask ended → identity-checked removal" path.
        provider.cancelSharedRunTaskForTesting(Self.endpointA)
        #expect(try await eventually { provider.sharedEntrySnapshot(for: Self.endpointA) == nil })

        let leaseB = try provider.acquire(Self.endpointA)
        let before = try #require(provider.sharedEntrySnapshot(for: Self.endpointA))
        #expect(before.generation != generationA)
        #expect(before.retainCount == 1)

        leaseA.release()

        let after = try #require(provider.sharedEntrySnapshot(for: Self.endpointA))
        #expect(after == before)

        // B is still in use, so a sweep at any instant must not remove it.
        #expect(provider.sweep(now: .now + .seconds(365 * 24 * 3600)) == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.generation == before.generation)

        leaseB.release()
    }

    @Test("A runTask ended by a cancel removes its entry, and the next acquire creates a new generation")
    func endedRunTaskIsReplaced() async throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let first = try provider.acquire(Self.endpointA)
        first.release()
        provider.cancelSharedRunTaskForTesting(Self.endpointA)
        #expect(try await eventually { provider.sharedEntrySnapshot(for: Self.endpointA) == nil })

        let second = try provider.acquire(Self.endpointA)
        defer { second.release() }

        #expect(first.client !== second.client)
        #expect(provider.createdSharedConnectionCount == 2)
    }

    // MARK: - Shared: idle retention

    @Test("sweep removes only entries that are not in use and idle past the TTL")
    func sweepRemovesOnlyIdleExpiredEntries() throws {
        let provider = makeProvider(idleTimeout: .seconds(3600))
        defer { provider.shutdown() }

        let inUse = try provider.acquire(Self.endpointA)
        defer { inUse.release() }
        let idle = try provider.acquire(Self.endpointB)
        idle.release()
        let releasedAt = try #require(provider.sharedEntrySnapshot(for: Self.endpointB)).lastUsed

        // Not past the TTL yet: nothing is touched.
        #expect(provider.sweep(now: releasedAt + .seconds(3599)) == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointB) != nil)

        // Past the TTL: only the idle one is removed; A, in use, stays however long it has been.
        #expect(provider.sweep(now: releasedAt + .seconds(3601)) == 1)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointB) == nil)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA) != nil)
    }

    @Test("An entry acquired just before a sweep is not removed")
    func acquireBeforeSweepKeepsEntry() throws {
        let provider = makeProvider(idleTimeout: .seconds(3600))
        defer { provider.shutdown() }

        let old = try provider.acquire(Self.endpointA)
        old.release()
        let staleInstant = try #require(provider.sharedEntrySnapshot(for: Self.endpointA)).lastUsed + .seconds(7200)

        let lease = try provider.acquire(Self.endpointA)
        #expect(provider.sweep(now: staleInstant) == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 1)

        lease.release()
    }

    @Test("An endpoint reclaimed by sweep gets a new connection on the next acquire")
    func sweptEndpointGetsFreshConnection() throws {
        let provider = makeProvider(idleTimeout: .seconds(1))
        defer { provider.shutdown() }

        let first = try provider.acquire(Self.endpointA)
        first.release()
        let lastUsed = try #require(provider.sharedEntrySnapshot(for: Self.endpointA)).lastUsed
        #expect(provider.sweep(now: lastUsed + .seconds(2)) == 1)

        let second = try provider.acquire(Self.endpointA)
        defer { second.release() }
        #expect(first.client !== second.client)
        #expect(provider.createdSharedConnectionCount == 2)
    }

    // MARK: - Shared: read purpose

    @Test("acquire(purpose: .read) opens a second shared connection to the endpoint, counted and snapshotted apart from the main one")
    func readPurposeIsASecondConnection() throws {
        let transports = RecordingTransportProvider()
        var settings = ClientSettings.localhost()
        settings.transportProvider = transports
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        defer { provider.shutdown() }

        let main = try provider.acquire(Self.endpointA)
        let read = try provider.acquire(Self.endpointA, purpose: .read)
        #expect(main.client !== read.client)
        #expect(provider.createdSharedConnectionCount == 1)
        #expect(provider.createdReadConnectionCount == 1)
        #expect(transports.endpoints == [Self.endpointA, Self.endpointA])
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 1)
        #expect(provider.readEntrySnapshot(for: Self.endpointA)?.retainCount == 1)

        // A second read lease reuses the read connection.
        let again = try provider.acquire(Self.endpointA, purpose: .read)
        #expect(again.client === read.client)
        #expect(provider.createdReadConnectionCount == 1)
        again.release()

        read.release()
        #expect(provider.readEntrySnapshot(for: Self.endpointA)?.retainCount == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 1)
        main.release()
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 0)
        #expect(provider.readEntrySnapshot(for: Self.endpointA)?.retainCount == 0)
    }

    @Test("sweep retires an idle read connection and shutdown closes both purposes")
    func sweepAndShutdownCoverTheReadPurpose() throws {
        let provider = makeProvider(idleTimeout: .seconds(1))

        let main = try provider.acquire(Self.endpointA)
        let read = try provider.acquire(Self.endpointA, purpose: .read)
        main.release()
        read.release()
        let lastUsed = max(
            try #require(provider.sharedEntrySnapshot(for: Self.endpointA)).lastUsed,
            try #require(provider.readEntrySnapshot(for: Self.endpointA)).lastUsed
        )
        #expect(provider.sweep(now: lastUsed + .seconds(2)) == 2)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA) == nil)
        #expect(provider.readEntrySnapshot(for: Self.endpointA) == nil)

        // Both purposes come back as new connections, then shutdown closes both.
        let mainAgain = try provider.acquire(Self.endpointA)
        let readAgain = try provider.acquire(Self.endpointA, purpose: .read)
        #expect(provider.createdSharedConnectionCount == 2)
        #expect(provider.createdReadConnectionCount == 2)
        provider.shutdown()
        mainAgain.release()
        readAgain.release()
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA) == nil)
        #expect(provider.readEntrySnapshot(for: Self.endpointA) == nil)
        #expect(throws: KurrentError.connectionClosed) {
            try provider.acquire(Self.endpointA, purpose: .read)
        }
    }

    @Test("A read connection whose run task ends is removed without touching the main connection")
    func readRunTaskEndRemovesOnlyTheReadEntry() async throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let main = try provider.acquire(Self.endpointA)
        let read = try provider.acquire(Self.endpointA, purpose: .read)
        defer { main.release() }
        provider.cancelSharedRunTaskForTesting(Self.endpointA, purpose: .read)
        #expect(try await eventually { provider.readEntrySnapshot(for: Self.endpointA) == nil })
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 1)

        // The late release of the old read lease touches neither entry.
        let fresh = try provider.acquire(Self.endpointA, purpose: .read)
        defer { fresh.release() }
        read.release()
        #expect(provider.readEntrySnapshot(for: Self.endpointA)?.retainCount == 1)
        #expect(provider.createdReadConnectionCount == 2)
        #expect(provider.createdSharedConnectionCount == 1)
    }

    // MARK: - Dedicated

    @Test("A dedicated connection is new every time; close unregisters it and is idempotent")
    func dedicatedConnectionsAreRegisteredAndClosedIdempotently() throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let a = try provider.openDedicated(for: Self.endpointA)
        let b = try provider.openDedicated(for: Self.endpointA)
        #expect(a.client !== b.client)
        #expect(provider.activeDedicatedConnectionCount == 2)
        #expect(provider.createdSharedConnectionCount == 0)

        a.close()
        a.close()
        #expect(provider.activeDedicatedConnectionCount == 1)

        b.close()
        #expect(provider.activeDedicatedConnectionCount == 0)
    }

    /// A subscription a helper returned must keep working after the client, the facade and the Node are all
    /// released: the handle of a dedicated connection has to keep the provider alive until it closes itself.
    @Test("The handle of a dedicated connection keeps the provider alive until it closes")
    func dedicatedHandleKeepsProviderAlive() throws {
        weak var weakProvider: ConnectionProvider?
        var handle: DedicatedConnection?

        do {
            let provider = makeProvider()
            weakProvider = provider
            handle = try provider.openDedicated(for: Self.endpointA)
        }
        #expect(weakProvider != nil)

        handle?.close()
        handle = nil
        #expect(weakProvider == nil)
    }

    // MARK: - Transport provider

    @Test("Every new connection is built by the settings' transport provider, for the endpoint it serves")
    func connectionsComeFromTransportProvider() throws {
        let transports = RecordingTransportProvider()
        var settings = ClientSettings.localhost()
        settings.transportProvider = transports
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(1), sweepInterval: nil)
        defer { provider.shutdown() }

        let first = try provider.acquire(Self.endpointA)
        let reused = try provider.acquire(Self.endpointA)
        first.release()
        reused.release()
        #expect(transports.endpoints == [Self.endpointA])

        let dedicated = try provider.openDedicated(for: Self.endpointB)
        dedicated.close()
        #expect(transports.endpoints == [Self.endpointA, Self.endpointB])

        // A retired shared connection is rebuilt through the provider too.
        let lastUsed = try #require(provider.sharedEntrySnapshot(for: Self.endpointA)).lastUsed
        #expect(provider.sweep(now: lastUsed + .seconds(2)) == 1)
        let rebuilt = try provider.acquire(Self.endpointA)
        rebuilt.release()
        #expect(transports.endpoints == [Self.endpointA, Self.endpointB, Self.endpointA])
    }

    @Test("A transport provider that throws fails the call with a KurrentError and registers no connection")
    func throwingTransportProviderFailsCall() throws {
        var settings = ClientSettings.localhost()
        settings.transportProvider = ThrowingTransportProvider()
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        defer { provider.shutdown() }

        #expect(throws: KurrentError.self) {
            try provider.acquire(Self.endpointA)
        }
        #expect(throws: KurrentError.self) {
            try provider.openDedicated(for: Self.endpointA)
        }
        #expect(provider.createdSharedConnectionCount == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA) == nil)
        #expect(provider.createdDedicatedConnectionCount == 0)
    }

    /// A method no service implements; `RecordingTransport` fails every call before encoding.
    private static let probeMethod = MethodDescriptor(fullyQualifiedService: "kurrentdb.test.Recording", method: "Probe")

    @Test("The transport a provider builds carries the connection and its calls, until the provider shuts down")
    func providerTransportCarriesConnection() async throws {
        let transports = RecordingTransportProvider()
        var settings = ClientSettings.localhost()
        settings.transportProvider = transports
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        defer { provider.shutdown() }

        let lease = try provider.acquire(Self.endpointA)
        let transport = try #require(transports.transports.first)
        #expect(try await eventually { transport.wasConnected })

        await #expect(throws: RecordingTransport.callFailure) {
            try await lease.client.unary(
                request: ClientRequest(message: []),
                descriptor: Self.probeMethod,
                serializer: RawBytes(),
                deserializer: RawBytes(),
                options: .defaults
            ) { try $0.message }
        }
        #expect(transport.calledMethods == [Self.probeMethod])

        lease.release()
        provider.shutdown()
        #expect(try await eventually { transport.wasDisconnected })
    }

    @Test("AnyClientTransport passes through the method config, retry throttle, errors and cancellation of the transport it wraps")
    func erasedTransportForwards() async throws {
        let config = MethodConfig(names: [], timeout: .seconds(7))
        let throttle = RetryThrottle(maxTokens: 7, tokenRatio: 0.5)
        let recording = RecordingTransport(methodConfig: config, retryThrottle: throttle)
        let transport = AnyClientTransport(recording)
        #expect(transport.config(forMethod: Self.probeMethod) == config)
        #expect(transport.retryThrottle === throttle)

        await #expect(throws: RecordingTransport.callFailure) {
            try await transport.withStream(descriptor: Self.probeMethod, options: .defaults) { _, _ in }
        }
        #expect(recording.calledMethods == [Self.probeMethod])

        // A call already waiting in the wrapped transport ends when its task is cancelled.
        let holding = RecordingTransport(holdsCalls: true)
        let held = AnyClientTransport(holding)
        let call = Task {
            try await held.withStream(descriptor: Self.probeMethod, options: .defaults) { _, _ in }
        }
        defer { call.cancel() }
        #expect(try await eventually { holding.calledMethods == [Self.probeMethod] })
        call.cancel()
        await #expect(throws: CancellationError.self) {
            try await call.value
        }
    }

    // MARK: - Shutdown

    @Test("A shutdown handler runs once, outside the lock, before the run tasks are cancelled; one registered after shutdown runs at once")
    func shutdownHandlersRunBeforeCancellation() async throws {
        let transports = RecordingTransportProvider()
        var settings = ClientSettings.localhost()
        settings.transportProvider = transports
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        let lease = try provider.acquire(Self.endpointA)
        let transport = try #require(transports.transports.first)
        // Cancellation only reaches connect() once it runs; before that the check below would pass either way.
        #expect(try await eventually { transport.wasConnected })

        let sawConnectionStillUp = Mutex(false)
        let runs = Mutex(0)
        let id = provider.registerShutdownHandler {
            runs.withLock { $0 += 1 }
            sawConnectionStillUp.withLock { $0 = !transport.connectWasCancelled }
            // Outside the lock: a handler may call back into the provider without deadlocking.
            _ = provider.isShutdown
            _ = provider.shutdownHandlerCount
        }
        #expect(id != 0)
        #expect(provider.shutdownHandlerCount == 1)

        provider.shutdown()
        #expect(runs.withLock { $0 } == 1)
        #expect(sawConnectionStillUp.withLock { $0 })
        #expect(transport.connectWasCancelled)
        #expect(provider.shutdownHandlerCount == 0)

        provider.shutdown()   // idempotent: the handler does not run again
        provider.removeShutdownHandler(id)   // no-op after shutdown
        #expect(runs.withLock { $0 } == 1)

        let late = Mutex(false)
        let lateID = provider.registerShutdownHandler { late.withLock { $0 = true } }
        #expect(late.withLock { $0 })
        #expect(lateID == 0)
        #expect(provider.shutdownHandlerCount == 0)
        lease.release()
    }

    @Test("shutdownAwaitingHandlers() returns only after the handlers of a shutdown already in progress on another thread have run; a second plain shutdown() does not wait")
    func shutdownAwaitingHandlersJoinsAnInProgressShutdown() async throws {
        let provider = makeProvider()
        let started = Mutex(false)
        let mayFinish = Mutex(false)
        let events = Mutex<[String]>([])
        _ = provider.registerShutdownHandler {
            started.withLock { $0 = true }
            while !mayFinish.withLock({ $0 }) { usleep(1_000) }
            events.withLock { $0.append("handler finished") }
        }
        Thread { provider.shutdown() }.start()
        #expect(try await eventually { started.withLock { $0 } })

        // The narrowed guarantee of shutdown(): only the caller that performs it waits for the handlers.
        provider.shutdown()
        #expect(events.withLock { $0 }.isEmpty)

        let waiter = Task {
            await provider.shutdownAwaitingHandlers()
            events.withLock { $0.append("waiter returned") }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(events.withLock { $0 }.isEmpty)

        mayFinish.withLock { $0 = true }
        await waiter.value
        #expect(events.withLock { $0 } == ["handler finished", "waiter returned"])

        // Once the handlers have run it returns at once, also for a caller that comes late.
        await provider.shutdownAwaitingHandlers()
    }

    @Test("shutdownAwaitingHandlers() also waits for the close hooks of dedicated connections (how a Subscription ends) run by a shutdown in progress")
    func shutdownAwaitingHandlersWaitsForDedicatedCloseHooks() async throws {
        let provider = makeProvider()
        let events = Mutex<[String]>([])
        let started = Mutex(false)
        let mayFinish = Mutex(false)
        _ = provider.registerShutdownHandler {}
        let dedicated = try provider.openDedicated(for: Self.endpointA)
        dedicated.onClose {
            started.withLock { $0 = true }
            while !mayFinish.withLock({ $0 }) { usleep(1_000) }
            events.withLock { $0.append("dedicated hook finished") }
        }
        Thread { provider.shutdown() }.start()
        #expect(try await eventually { started.withLock { $0 } })

        let waiter = Task {
            await provider.shutdownAwaitingHandlers()
            events.withLock { $0.append("waiter returned") }
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(events.withLock { $0 }.isEmpty)

        mayFinish.withLock { $0 = true }
        await waiter.value
        #expect(events.withLock { $0 } == ["dedicated hook finished", "waiter returned"])
        dedicated.close()
    }

    @Test("shutdownAwaitingHandlers() on a running provider shuts it down and runs its handlers before returning")
    func shutdownAwaitingHandlersShutsDown() async {
        let provider = makeProvider()
        let ran = Mutex(false)
        _ = provider.registerShutdownHandler { ran.withLock { $0 = true } }
        await provider.shutdownAwaitingHandlers()
        #expect(provider.isShutdown)
        #expect(ran.withLock { $0 })
        #expect(provider.shutdownHandlerCount == 0)
    }

    @Test("A removed shutdown handler does not run")
    func removedShutdownHandlerDoesNotRun() {
        let provider = makeProvider()
        let removedRan = Mutex(false)
        let keptRan = Mutex(false)
        let removed = provider.registerShutdownHandler { removedRan.withLock { $0 = true } }
        _ = provider.registerShutdownHandler { keptRan.withLock { $0 = true } }
        #expect(provider.shutdownHandlerCount == 2)
        provider.removeShutdownHandler(removed)
        provider.removeShutdownHandler(removed)   // twice is a no-op
        #expect(provider.shutdownHandlerCount == 1)
        provider.shutdown()
        #expect(!removedRan.withLock { $0 })
        #expect(keptRan.withLock { $0 })
    }

    @Test("After shutdown, shared and dedicated admissions are both refused")
    func shutdownRejectsBothConnectionClasses() throws {
        let provider = makeProvider()
        let lease = try provider.acquire(Self.endpointA)
        let dedicated = try provider.openDedicated(for: Self.endpointA)

        provider.shutdown()

        #expect(throws: KurrentError.connectionClosed) {
            try provider.acquire(Self.endpointA)
        }
        #expect(throws: KurrentError.connectionClosed) {
            try provider.openDedicated(for: Self.endpointA)
        }
        #expect(provider.activeDedicatedConnectionCount == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA) == nil)

        // release and close after shutdown are no-ops and do not fail.
        lease.release()
        dedicated.close()
    }

    @Test("shutdown is idempotent")
    func shutdownIsIdempotent() throws {
        let provider = makeProvider()
        try provider.acquire(Self.endpointA).release()

        provider.shutdown()
        provider.shutdown()

        #expect(provider.createdSharedConnectionCount == 1)
    }

    /// A runTask may not have been scheduled yet when shutdown cancels it; it must still end normally
    /// after the cancel, and must not revive the closed provider.
    @Test("With shutdown before the runTask starts, the connection is still torn down and the provider stays closed")
    func shutdownBeforeRunTaskStarts() async throws {
        let provider = makeProvider()
        let lease = try provider.acquire(Self.endpointA)
        let dedicated = try provider.openDedicated(for: Self.endpointA)
        provider.shutdown()

        lease.release()
        dedicated.close()
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA) == nil)
        #expect(throws: KurrentError.connectionClosed) {
            try provider.acquire(Self.endpointA)
        }
    }

    @Test("An acquire or openDedicated racing shutdown is either refused or included in the shutdown")
    func admissionsRacingShutdownAreRejectedOrCancelled() async throws {
        for _ in 0 ..< 20 {
            let provider = makeProvider()

            let outcomes = await withTaskGroup(of: Bool.self) { group in
                for index in 0 ..< 20 {
                    group.addTask {
                        do {
                            if index.isMultiple(of: 2) {
                                try provider.acquire(Self.endpointA).release()
                            } else {
                                _ = try provider.openDedicated(for: Self.endpointB)
                            }
                            return true
                        } catch {
                            return false
                        }
                    }
                }
                group.addTask {
                    provider.shutdown()
                    return true
                }
                var results: [Bool] = []
                for await result in group {
                    results.append(result)
                }
                return results
            }

            #expect(outcomes.count == 21)
            // Whichever came first, no entry and no registration may remain after shutdown.
            #expect(provider.sharedEntrySnapshot(for: Self.endpointA) == nil)
            #expect(provider.activeDedicatedConnectionCount == 0)
        }
    }
}

@Suite("KurrentDBClient shutdown", .serialized, .timeLimit(.minutes(1)))
struct KurrentDBClientShutdownTests {
    @Test("The public shutdown is idempotent and closes the connection provider")
    func shutdownIsIdempotentAndClosesProvider() throws {
        let client = KurrentDBClient(settings: .localhost())

        client.shutdown()
        client.shutdown()

        #expect(client.selector.connections.isShutdown)
    }

    /// Whether or not the cached node has expired, select() must report connectionClosed at once after
    /// shutdown, instead of starting a discovery, retrying, and reporting "no node found" in the end.
    @Test("select() throws connectionClosed at once after shutdown")
    func selectAfterShutdownThrowsConnectionClosed() async throws {
        let client = KurrentDBClient(settings: .localhost())
        client.shutdown()

        await #expect(throws: KurrentError.connectionClosed) {
            try await client.selector.select()
        }
    }
}

/// Builds a `RecordingTransport` for every connection and records the endpoint it was built for.
/// (`Endpoint` alone is ambiguous in this file: grpc-swift-nio-transport declares one too.)
private final class RecordingTransportProvider: TransportProvider {
    private let built = Mutex<[(endpoint: KurrentDB.Endpoint, transport: RecordingTransport)]>([])

    /// The endpoint of every transport built so far, in order.
    var endpoints: [KurrentDB.Endpoint] {
        built.withLock { $0.map { $0.endpoint } }
    }

    /// Every transport built so far, in order.
    var transports: [RecordingTransport] {
        built.withLock { $0.map { $0.transport } }
    }

    func makeTransport(for endpoint: KurrentDB.Endpoint) throws -> any ClientTransport<AnyClientTransport.Bytes> {
        let transport = RecordingTransport()
        built.withLock { $0.append((endpoint, transport)) }
        return transport
    }
}

/// A transport that runs no RPC. It records each call the client starts on it and fails the call
/// with `callFailure`, or, built with `holdsCalls`, keeps the call waiting until its task is
/// cancelled. It hands back the method config and retry throttle it was built with, and stays
/// connected until it is shut down or the task running `connect()` is cancelled.
private final class RecordingTransport: ClientTransport {
    typealias Bytes = AnyClientTransport.Bytes

    static let callFailure = RPCError(code: .unavailable, message: "RecordingTransport runs no RPC")

    let retryThrottle: RetryThrottle?
    private let methodConfig: MethodConfig?
    private let holdsCalls: Bool
    private let state = Mutex(State())
    private let shutdown = AsyncStream<Void>.makeStream()

    private struct State {
        var calledMethods: [MethodDescriptor] = []
        var wasConnected = false
        var wasDisconnected = false
        var connectWasCancelled = false
    }

    init(methodConfig: MethodConfig? = nil, retryThrottle: RetryThrottle? = nil, holdsCalls: Bool = false) {
        self.methodConfig = methodConfig
        self.retryThrottle = retryThrottle
        self.holdsCalls = holdsCalls
    }

    /// The method of every call started on this transport, in order.
    var calledMethods: [MethodDescriptor] {
        state.withLock { $0.calledMethods }
    }

    /// Whether `connect()` has started.
    var wasConnected: Bool {
        state.withLock { $0.wasConnected }
    }

    /// Whether `connect()` has returned.
    var wasDisconnected: Bool {
        state.withLock { $0.wasDisconnected }
    }

    /// Whether the task running `connect()` has been cancelled. Set synchronously inside
    /// `Task.cancel()`, unlike ``wasDisconnected``, so a test can tell what ran before the cancel.
    var connectWasCancelled: Bool {
        state.withLock { $0.connectWasCancelled }
    }

    func connect() async throws {
        state.withLock { $0.wasConnected = true }
        defer { state.withLock { $0.wasDisconnected = true } }
        // Ends when the stream finishes or the task is cancelled.
        await withTaskCancellationHandler {
            for await _ in shutdown.stream {}
        } onCancel: {
            state.withLock { $0.connectWasCancelled = true }
        }
    }

    func beginGracefulShutdown() {
        shutdown.continuation.finish()
    }

    func withStream<T: Sendable>(
        descriptor: MethodDescriptor,
        options _: CallOptions,
        _: (_ stream: RPCStream<Inbound, Outbound>, _ context: ClientContext) async throws -> T
    ) async throws -> T {
        state.withLock { $0.calledMethods.append(descriptor) }
        if holdsCalls {
            try await Task.sleep(for: .seconds(3600))
        }
        throw Self.callFailure
    }

    func config(forMethod _: MethodDescriptor) -> MethodConfig? {
        methodConfig
    }
}

/// Passes `[UInt8]` messages through unchanged.
private struct RawBytes: MessageSerializer, MessageDeserializer {
    func serialize<Bytes: GRPCContiguousBytes>(_ message: [UInt8]) throws -> Bytes {
        Bytes(message)
    }

    func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> [UInt8] {
        serializedMessageBytes.withUnsafeBytes { Array($0) }
    }
}

private struct ThrowingTransportProvider: TransportProvider {
    struct Failure: Error {}

    func makeTransport(for _: KurrentDB.Endpoint) throws -> any ClientTransport<AnyClientTransport.Bytes> {
        throw Failure()
    }
}
