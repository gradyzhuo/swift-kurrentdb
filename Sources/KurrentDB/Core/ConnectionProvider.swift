//
//  ConnectionProvider.swift
//  swift-kurrentdb
//
// Where every gRPC connection of a KurrentDBClient is admitted and its lifetime managed.
//
// Named ConnectionProvider, not ConnectionPool, to stay clear of Sources/KurrentDBPool/.
// That KurrentDBPool pools independent databases that have nothing to do with each other (for
// test isolation), the opposite assumption to the one here (see tasks/todo-kurrentdb-pool.md).
// Sharing a name would mislead readers.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import NIOCore
import NIOPosix
import Synchronization

/// Manages two kinds of connections, chosen by whether the RPC **finishes inside** `perform(node:)`:
///
/// - **Shared** (``acquire(_:purpose:)``): calls that end inside `perform(node:)` and whose
///   connection never leaves that scope — single-message responses (`UnaryUnary`, `StreamUnary`)
///   and `UnaryStream` usecases whose `send()` drains the stream before returning (marked
///   `BufferedStreamResponse`: `Streams.Read`, `Streams.ReadAll`, `Projections.Statistics`,
///   `Users.Details`), plus gossip and server features. Up to two long-lived connections per
///   endpoint, one per ``ConnectionPurpose``: these calls share the `.main` one's HTTP/2 stream
///   budget. A lazy read (`ScopedStreamResponse`, `read()`) holds its lease, and an HTTP/2
///   stream, for as long as the iterator lives, so it takes the `.read` one: held reads queue
///   only behind each other above the server's per-connection stream limit, never in front of a
///   unary call. The `.read` connection opens on the first lazy read to the endpoint.
/// - **Dedicated** (``openDedicated(for:)``): RPCs that carry the stream out of `perform`
///   (subscriptions, persistent subscriptions, `Monitoring.Stats`, `StreamStream`). They may
///   hold an HTTP/2 stream slot indefinitely, so each call gets its own connection and never
///   competes for shared capacity. `BatchAppend` collects its responses inside the function
///   but still takes this path for now (see the comment in that file).
///
/// ## Why a Mutex and not an actor
///
/// `deinit` and the synchronous `KurrentDBClient.shutdown()` cannot `await`, and every action
/// needed here (publishing an entry, creating a Task, `Task.cancel()`) is synchronous. The expensive
/// part (building the transport: TLS builds an `NIOSSLContext` and may read certificate files) happens outside the lock.
///
/// ## Why teardown only ever cancels
///
/// `GRPCClient.beginGracefulShutdown()` on a client still `.notStarted` jumps straight to
/// `.stopped` without telling the transport; `runConnections()` then throws `clientIsStopped`. And a
/// graceful shutdown waits for a long-lived stream to end, which never happens. Cancelling the task
/// that runs `runConnections()` stops every RPC in progress, and the call itself returns normally
/// (see `GRPCClientLifecycleCharacterizationTests`).
///
/// Note that a cancel does not always take effect **at once**: for an address that does not answer
/// a SYN, a `runConnections()` that has started connecting returns only when that TCP connect times out
/// (about 10 seconds); a refused (ECONNREFUSED) or established connection returns at once. So sweep and
/// shutdown always remove the entry from the table before cancelling: nobody can get a client that is being torn down.
///
/// ## Reclaiming shared connections
///
/// Entries are not evicted on errors: `.deadlineExceeded`, UNAVAILABLE from the server and
/// `.notLeaderException` do not mean the transport is dead, and the transport reconnects after a transient
/// failure by itself. An entry is removed in two cases only: its runTask has really ended, or the background
/// sweeper finds it with `retainCount == 0` and idle for longer than `idleTimeout`. The second is needed: the
/// transport's `maxIdleTime` closes the socket but does not end the runTask, so stale endpoints from gossip and dead seeds would reconnect forever.
package final class ConnectionProvider: Sendable {
    package typealias Client = GRPCClient<AnyClientTransport>

    /// The key of a shared entry: one shared connection per endpoint and purpose.
    private struct SharedKey: Hashable {
        let endpoint: Endpoint
        let purpose: ConnectionPurpose
    }

    private struct SharedEntry {
        let generation: UInt64
        let client: Client
        let runTask: Task<Void, Never>
        var retainCount: Int
        var lastUsed: ContinuousClock.Instant
    }

    private struct State {
        var shared: [SharedKey: SharedEntry] = [:]
        var dedicated: [UInt64: DedicatedLifecycle] = [:]
        var nextID: UInt64 = 0
        var isShutdown = false
        var createdSharedConnectionCount = 0
        var createdReadConnectionCount = 0
        var createdDedicatedConnectionCount = 0
        var sweeper: Task<Void, Never>?
        var shutdownHandlers: [ShutdownHandlerID: @Sendable () -> Void] = [:]
        /// Set by the caller that performs the shutdown once it has run every shutdown handler and
        /// every dedicated connection's close hook.
        var shutdownHasRun = false
        /// Callers of `shutdownAwaitingHandlers()` waiting for `shutdownHasRun`.
        var shutdownHandlerWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let settings: ClientSettings
    private let idleTimeout: Duration

    /// The event-loop group every Posix transport this provider builds runs on (a
    /// `TransportProvider` in the settings chooses its own loops). Never shut down here.
    package let eventLoopGroup: any EventLoopGroup
    private let state = Mutex(State())

    /// - Parameters:
    ///   - eventLoopGroup: The group the Posix transports run on; the client passes the one it was given.
    ///   - idleTimeout: How long a shared connection stays idle, with no call in progress, before it is reclaimed.
    ///   - sweepInterval: How often the background sweeper checks; `nil` starts no sweeper
    ///     (for tests, which drive ``sweep(now:)`` by hand).
    package init(
        settings: ClientSettings,
        eventLoopGroup: any EventLoopGroup = .singletonMultiThreadedEventLoopGroup,
        idleTimeout: Duration = .seconds(3600),
        sweepInterval: Duration? = .seconds(60)
    ) {
        self.settings = settings
        self.eventLoopGroup = eventLoopGroup
        self.idleTimeout = idleTimeout

        guard let sweepInterval else { return }
        // weak: the sweeper must not keep the provider alive. The strong reference lasts for one sweep
        // and never across the next sleep. If the provider deinits when that reference is released, deinit
        // only cancels this task and does not wait for it, so it cannot deadlock on itself.
        let sweeper = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: sweepInterval)
                } catch {
                    return
                }
                guard let self else { return }
                self.sweep(now: .now)
            }
        }
        state.withLock { $0.sweeper = sweeper }
    }

    deinit {
        shutdown()
    }

    // MARK: - Shared connections

    /// Returns the shared connection for `purpose` on `endpoint`, and adds one to its retainCount.
    ///
    /// The caller must call ``SharedLease/release()`` when the call ends: in `perform(node:)`, with
    /// `defer { lease.release() }`. Lookup or publication and the retainCount increment happen under one
    /// lock, so the sweeper cannot remove the entry between the lookup and the increment.
    ///
    /// - Parameter purpose: `.main` (the default) for every call that ends inside `perform`;
    ///   `.read` for a lazy read, which holds its stream for as long as the caller iterates.
    ///   Each purpose is its own connection, entry, generation and idle clock.
    /// - Throws: `KurrentError.connectionClosed` if the provider has shut down;
    ///   the matching `KurrentError` if building the transport fails.
    package func acquire(_ endpoint: Endpoint, purpose: ConnectionPurpose = .main) throws(KurrentError) -> SharedLease {
        let key = SharedKey(endpoint: endpoint, purpose: purpose)
        if let lease = try retainExisting(key, now: .now) {
            return lease
        }

        // Miss: build outside the lock (TLS is expensive), then publish under the lock.
        let candidate = try makeClient(for: endpoint)
        let (lease, published) = try state.withLock { state throws(KurrentError) -> (SharedLease, Bool) in
            guard !state.isShutdown else {
                throw KurrentError.connectionClosed
            }
            let now = ContinuousClock.now
            // Someone published while we were building: use theirs and drop ours (it never ran, so releasing it is enough).
            if var existing = state.shared[key] {
                existing.retainCount += 1
                existing.lastUsed = now
                state.shared[key] = existing
                return (SharedLease(provider: self, endpoint: endpoint, purpose: purpose, generation: existing.generation, client: existing.client), false)
            }
            // Create the runTask and publish the complete entry under one lock: there is never an entry that is
            // visible without a task to cancel, nor a task that escaped registration.
            state.nextID += 1
            let generation = state.nextID
            let runTask = makeSharedRunTask(client: candidate, key: key, generation: generation)
            state.shared[key] = SharedEntry(
                generation: generation,
                client: candidate,
                runTask: runTask,
                retainCount: 1,
                lastUsed: now
            )
            switch purpose {
            case .main: state.createdSharedConnectionCount += 1
            case .read: state.createdReadConnectionCount += 1
            }
            return (SharedLease(provider: self, endpoint: endpoint, purpose: purpose, generation: generation, client: candidate), true)
        }
        if published {
            logger.debug("[ConnectionProvider] Opened shared \(purpose) connection to \(endpoint.debugDescription)")
        }
        return lease
    }

    private func retainExisting(_ key: SharedKey, now: ContinuousClock.Instant) throws(KurrentError) -> SharedLease? {
        try state.withLock { state throws(KurrentError) -> SharedLease? in
            guard !state.isShutdown else {
                throw KurrentError.connectionClosed
            }
            guard var entry = state.shared[key] else {
                return nil
            }
            entry.retainCount += 1
            entry.lastUsed = now
            state.shared[key] = entry
            return SharedLease(provider: self, endpoint: key.endpoint, purpose: key.purpose, generation: entry.generation, client: entry.client)
        }
    }

    /// Takes effect only when the generation matches. Does nothing when the entry was removed or replaced by
    /// a newer generation: a late release must never touch the count of the entry that replaced it.
    fileprivate func release(_ endpoint: Endpoint, purpose: ConnectionPurpose, generation: UInt64) {
        let key = SharedKey(endpoint: endpoint, purpose: purpose)
        let now = ContinuousClock.now
        state.withLock { state in
            guard var entry = state.shared[key], entry.generation == generation else {
                return
            }
            entry.retainCount = max(0, entry.retainCount - 1)
            entry.lastUsed = now
            state.shared[key] = entry
        }
    }

    private func makeSharedRunTask(client: Client, key: SharedKey, generation: UInt64) -> Task<Void, Never> {
        Task { [weak self] in
            await Self.run(client, endpoint: key.endpoint)
            // weak self is resolved only at teardown, and is not promoted to a strong reference across the await above.
            self?.sharedRunTaskEnded(key, generation: generation)
        }
    }

    private func sharedRunTaskEnded(_ key: SharedKey, generation: UInt64) {
        let removed = state.withLock { state -> Bool in
            guard state.shared[key]?.generation == generation else {
                return false
            }
            state.shared[key] = nil
            return true
        }
        if removed {
            logger.debug("[ConnectionProvider] Shared \(key.purpose) connection to \(key.endpoint.debugDescription) ended; removed from cache")
        }
    }

    /// Removes every shared entry with `retainCount == 0` that has been idle for longer than `idleTimeout`, of both purposes.
    ///
    /// The background sweeper calls it with `.now`; tests can pass any instant.
    ///
    /// - Returns: The number of entries removed.
    @discardableResult
    package func sweep(now: ContinuousClock.Instant) -> Int {
        let expired = state.withLock { state -> [(SharedKey, Task<Void, Never>)] in
            let expired = state.shared.filter { _, entry in
                entry.retainCount == 0 && now - entry.lastUsed > idleTimeout
            }
            for key in expired.keys {
                state.shared[key] = nil
            }
            return expired.map { ($0.key, $0.value.runTask) }
        }
        // Cancel only the old tasks captured here; a newer generation that an acquire created meanwhile is not affected.
        for (key, runTask) in expired {
            logger.debug("[ConnectionProvider] Retiring idle shared \(key.purpose) connection to \(key.endpoint.debugDescription)")
            runTask.cancel()
        }
        return expired.count
    }

    // MARK: - Dedicated connections

    /// Opens a dedicated connection for one call that carries its stream out of `perform`, and
    /// registers it with the provider.
    ///
    /// Registration is atomic: racing ``shutdown()``, it is either refused or included in the set shutdown cancels.
    /// The returned handle holds the provider strongly until ``DedicatedConnection/close()``, so a
    /// subscription a helper returned is not interrupted when the client or the facade is released.
    ///
    /// - Throws: `KurrentError.connectionClosed` if the provider has shut down.
    package func openDedicated(for endpoint: Endpoint) throws(KurrentError) -> DedicatedConnection {
        // Check first: after shutdown there is no need to build a transport, and the caller gets connectionClosed
        // rather than a build failure. The second check before publishing is still needed, for a shutdown during the build.
        guard !isShutdown else {
            throw .connectionClosed
        }
        let client = try makeClient(for: endpoint)
        return try state.withLock { state throws(KurrentError) -> DedicatedConnection in
            guard !state.isShutdown else {
                throw KurrentError.connectionClosed
            }
            state.nextID += 1
            let id = state.nextID
            state.createdDedicatedConnectionCount += 1
            // This task captures neither the provider nor the handle: the registry → task edge forms no cycle.
            let runTask = Task {
                await Self.run(client, endpoint: endpoint)
            }
            let lifecycle = DedicatedLifecycle(runTask: runTask)
            state.dedicated[id] = lifecycle
            return DedicatedConnection(provider: self, id: id, client: client, lifecycle: lifecycle)
        }
    }

    fileprivate func deregisterDedicated(_ id: UInt64) {
        state.withLock { state in
            state.dedicated[id] = nil
        }
    }

    // MARK: - Shutdown handlers

    /// Identifies a handler registered with ``registerShutdownHandler(_:)``. Never 0 for a handler
    /// that was stored; 0 means it already ran because the provider was shut down.
    package typealias ShutdownHandlerID = UInt64

    /// Runs `handler` once when the provider shuts down, outside the lock, before any run task is
    /// cancelled; runs it immediately (and returns 0) if the provider is already shut down.
    ///
    /// For a call that holds a shared connection beyond one `perform` (a lazy read, on either of its
    /// delivery paths): the handler ends the call with `KurrentError.connectionClosed` before the
    /// transport is torn down, so the caller sees why the call ended instead of whatever error the
    /// teardown produces (which `withRetry` would take for a node failure). Also for a wait that a
    /// shutdown must end at once (``sleepUnlessShutDown(for:)``). It must be synchronous,
    /// must not block, and must capture only what it needs to end the call, never the call's owner:
    /// the registry keeps it alive until it is removed or run. A handler may call back into the
    /// provider. Remove it with ``removeShutdownHandler(_:)`` when the call ends.
    package func registerShutdownHandler(_ handler: @escaping @Sendable () -> Void) -> ShutdownHandlerID {
        let id: ShutdownHandlerID? = state.withLock { state in
            guard !state.isShutdown else { return nil }
            state.nextID += 1
            state.shutdownHandlers[state.nextID] = handler
            return state.nextID
        }
        guard let id else {
            handler()
            return 0
        }
        return id
    }

    /// Removes a handler so it does not run at shutdown. A no-op for 0, for an id already removed,
    /// and after shutdown (the handler has run or is running).
    package func removeShutdownHandler(_ id: ShutdownHandlerID) {
        guard id != 0 else { return }
        state.withLock { state in
            state.shutdownHandlers[id] = nil
        }
    }

    /// For tests: how many shutdown handlers are registered.
    package var shutdownHandlerCount: Int {
        state.withLock { $0.shutdownHandlers.count }
    }

    // MARK: - Back-off

    /// Sleeps for `duration`, waking early when the provider shuts down or the calling task is
    /// cancelled. For a wait between attempts (the node-discovery back-off): a shutdown must end it
    /// at once, but `Task.sleep` only wakes on its own task's cancellation, and `shutdown()` cannot
    /// cancel its caller's task. So the sleep runs in a task of its own, which a shutdown handler
    /// cancels; the caller's cancellation is forwarded to it.
    ///
    /// - Throws: `KurrentError.connectionClosed` if the provider is shut down when the sleep ends,
    ///   also when it already was; `CancellationError` if the calling task was cancelled.
    package func sleepUnlessShutDown(for duration: Duration) async throws {
        let sleeper = Task { try await Task.sleep(for: duration) }
        let handler = registerShutdownHandler { sleeper.cancel() }
        defer { removeShutdownHandler(handler) }
        await withTaskCancellationHandler {
            _ = await sleeper.result
        } onCancel: {
            sleeper.cancel()
        }
        if isShutdown {
            throw KurrentError.connectionClosed
        }
        try Task.checkCancellation()
    }

    // MARK: - Shutdown

    /// Refuses every later admission, and cancels every shared connection (both purposes), every registered dedicated connection and the sweeper. Idempotent.
    ///
    /// Order: under the lock it marks the provider shut down and takes everything; outside it, it
    /// first runs the registered shutdown handlers (synchronously, in registration order), then
    /// cancels the shared run tasks and the sweeper, then terminates the dedicated connections. The
    /// handlers go first so each call they end reports `connectionClosed` before cancelling a run
    /// task fails it as a transport error (the pattern of `DedicatedLifecycle.terminate()`). For the
    /// caller that performs the shutdown, every handler and every dedicated connection's close hook
    /// has run when this returns, so a call that held a connection has ended by then, even though
    /// the transports may still be tearing down. A caller that finds a shutdown already in progress
    /// returns at once, possibly while that shutdown is still running them; use
    /// ``shutdownAwaitingHandlers()`` to wait for them.
    ///
    /// This **starts** the close: the connections are not guaranteed to be closed when it returns.
    package func shutdown() {
        let taken = state.withLock { state -> (handlers: [@Sendable () -> Void], tasks: [Task<Void, Never>], dedicated: [DedicatedLifecycle])? in
            guard !state.isShutdown else {
                return nil
            }
            state.isShutdown = true
            let handlers = state.shutdownHandlers.sorted { $0.key < $1.key }.map(\.value)
            var tasks = state.shared.values.map(\.runTask)
            if let sweeper = state.sweeper {
                tasks.append(sweeper)
            }
            let dedicated = Array(state.dedicated.values)
            state.shutdownHandlers.removeAll()
            state.shared.removeAll()
            state.dedicated.removeAll()
            state.sweeper = nil
            return (handlers, tasks, dedicated)
        }
        // Another caller performs the shutdown; `shutdownAwaitingHandlers()` waits for it.
        guard let taken else { return }
        for handler in taken.handlers {
            handler()
        }
        for task in taken.tasks {
            task.cancel()
        }
        for lifecycle in taken.dedicated {
            lifecycle.terminate()
        }
        // Last: a caller of `shutdownAwaitingHandlers()` proceeds only once the dedicated
        // connections' close hooks (how a `Subscription` ends) have run too.
        let waiters = state.withLock { state in
            state.shutdownHasRun = true
            defer { state.shutdownHandlerWaiters.removeAll() }
            return state.shutdownHandlerWaiters
        }
        for waiter in waiters {
            waiter.resume()
        }
    }

    /// Shuts the provider down like ``shutdown()`` and returns once that shutdown has run every
    /// shutdown handler (which ends lazy reads) and every dedicated connection's
    /// ``DedicatedConnection/onClose(_:)`` hook (which ends subscriptions), also when another
    /// caller's shutdown started first and is still running them (a plain second ``shutdown()`` returns at once). For a caller that must not
    /// proceed while a call that held a connection may still be ending, such as `KurrentDBPool`
    /// handing the instance to the next borrower. Not cancellable: the handlers and hooks are
    /// synchronous and short, so it waits for them even when the calling task is cancelled.
    package func shutdownAwaitingHandlers() async {
        shutdown()
        await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
            let haveRun = state.withLock { state in
                guard !state.shutdownHasRun else { return true }
                state.shutdownHandlerWaiters.append(waiter)
                return false
            }
            if haveRun {
                waiter.resume()
            }
        }
    }

    /// Whether the provider has shut down.
    package var isShutdown: Bool {
        state.withLock { $0.isShutdown }
    }

    // MARK: - Introspection (tests)

    /// How many `.main` shared connections have been created so far. It only grows; it counts `GRPCClient`s created, not TCP connections or
    /// TLS handshakes: the transport's own reconnects do not add to it. `.read` connections are counted in
    /// ``createdReadConnectionCount``.
    package var createdSharedConnectionCount: Int {
        state.withLock { $0.createdSharedConnectionCount }
    }

    /// How many `.read` shared connections (the ones lazy reads hold their streams on) have been
    /// created so far. Monotonic, counted like ``createdSharedConnectionCount``.
    package var createdReadConnectionCount: Int {
        state.withLock { $0.createdReadConnectionCount }
    }

    /// How many dedicated connections have been created so far. Monotonic; the counterpart of
    /// ``createdSharedConnectionCount`` and the way to tell which path a call took —
    /// ``activeDedicatedConnectionCount`` returns to 0 once a dedicated connection closes, so
    /// it cannot distinguish them.
    package var createdDedicatedConnectionCount: Int {
        state.withLock { $0.createdDedicatedConnectionCount }
    }

    /// The number of dedicated connections registered now.
    package var activeDedicatedConnectionCount: Int {
        state.withLock { $0.dedicated.count }
    }

    package struct SharedEntrySnapshot: Equatable, Sendable {
        package let generation: UInt64
        package let retainCount: Int
        package let lastUsed: ContinuousClock.Instant
    }

    /// For tests: looks at the current `.main` shared entry of an endpoint.
    package func sharedEntrySnapshot(for endpoint: Endpoint) -> SharedEntrySnapshot? {
        entrySnapshot(SharedKey(endpoint: endpoint, purpose: .main))
    }

    /// For tests: the endpoint's current `.read` shared entry, the one lazy reads use.
    package func readEntrySnapshot(for endpoint: Endpoint) -> SharedEntrySnapshot? {
        entrySnapshot(SharedKey(endpoint: endpoint, purpose: .read))
    }

    private func entrySnapshot(_ key: SharedKey) -> SharedEntrySnapshot? {
        state.withLock { state in
            state.shared[key].map {
                SharedEntrySnapshot(generation: $0.generation, retainCount: $0.retainCount, lastUsed: $0.lastUsed)
            }
        }
    }

    /// For tests: cancels the runTask of a shared entry **without** removing the entry, to take the real
    /// "runTask ended → identity-checked removal" path.
    package func cancelSharedRunTaskForTesting(_ endpoint: Endpoint, purpose: ConnectionPurpose = .main) {
        let runTask = state.withLock { $0.shared[SharedKey(endpoint: endpoint, purpose: purpose)]?.runTask }
        runTask?.cancel()
    }

    // MARK: - Private

    private static func run(_ client: Client, endpoint: Endpoint) async {
        do {
            try await client.runConnections()
        } catch let error as RuntimeError where error.code == .clientIsStopped {
            // Normal teardown: the client was stopped before the task started.
        } catch {
            // Five call sites used to swallow this error, which left connection failures impossible to diagnose.
            logger.error("[ConnectionProvider] Connection to \(endpoint.debugDescription) terminated with error: \(error)")
        }
    }

    private func makeClient(for endpoint: Endpoint) throws(KurrentError) -> Client {
        let settings = settings
        let eventLoopGroup = eventLoopGroup
        let transport: AnyClientTransport = try withRethrowingError(usage: "ConnectionProvider.makeClient(for:)") {
            if let provider = settings.transportProvider {
                return try AnyClientTransport(provider.makeTransport(for: endpoint))
            }
            let posix: HTTP2ClientTransport.Posix = try .http2NIOPosix(
                target: endpoint.target,
                transportSecurity: settings.transportSecurity,
                config: .defaults { config in
                    // ClientSettings.keepAlive used to be parsed and never passed to the transport (which has
                    // keepalive off by default). allowWithoutCalls: false, so no new idle-ping behaviour is
                    // introduced; idle shared connections are left to the transport's maxIdleTime and this class's sweeper.
                    config.connection.keepalive = .init(
                        time: settings.keepAlive.interval,
                        timeout: settings.keepAlive.timeout,
                        allowWithoutCalls: false
                    )
                },
                eventLoopGroup: eventLoopGroup
            )
            return AnyClientTransport(posix)
        }
        return GRPCClient(transport: transport)
    }
}

/// Which of an endpoint's two shared connections a call uses (see ``ConnectionProvider``).
package enum ConnectionPurpose: Hashable, Sendable {
    /// Unary calls, `.buffered` reads, gossip, server features: everything that ends inside `perform`.
    case main
    /// Lazy reads, which hold their stream for as long as the caller iterates.
    case read
}

/// The right to use a shared connection once. Released in `perform(node:)` with `defer { lease.release() }`.
package final class SharedLease: Sendable {
    package let client: ConnectionProvider.Client
    private let provider: ConnectionProvider
    private let endpoint: Endpoint
    private let purpose: ConnectionPurpose
    private let generation: UInt64
    private let released = Mutex(false)

    fileprivate init(provider: ConnectionProvider, endpoint: Endpoint, purpose: ConnectionPurpose, generation: UInt64, client: ConnectionProvider.Client) {
        self.provider = provider
        self.endpoint = endpoint
        self.purpose = purpose
        self.generation = generation
        self.client = client
    }

    /// Only the first call has an effect.
    package func release() {
        let first = released.withLock { released in
            defer { released = true }
            return !released
        }
        guard first else { return }
        provider.release(endpoint, purpose: purpose, generation: generation)
    }

    deinit {
        release()
    }
}

/// The part of a dedicated connection that both its handle and the provider's registry need:
/// the run task plus the hooks to run when it is terminated. It holds no reference to the
/// provider, so the registry -> lifecycle edge cannot form a cycle.
package final class DedicatedLifecycle: Sendable {
    private struct State {
        var terminated = false
        var hooks: [@Sendable () -> Void] = []
    }

    private let runTask: Task<Void, Never>
    private let state = Mutex(State())

    fileprivate init(runTask: Task<Void, Never>) {
        self.runTask = runTask
    }

    /// Idempotent. Runs the registered hooks (outside the lock), then cancels the run task.
    /// Hooks go first: cancelling the run task makes the transport fail the call, and that
    /// failure would reach a hand-off before the hook could tell it the close was deliberate.
    fileprivate func terminate() {
        let hooks: [@Sendable () -> Void]? = state.withLock { state in
            guard !state.terminated else { return nil }
            state.terminated = true
            let hooks = state.hooks
            state.hooks = []
            return hooks
        }
        guard let hooks else { return }
        for hook in hooks { hook() }
        runTask.cancel()
    }

    /// Runs `hook` once after termination; immediately if already terminated.
    fileprivate func onTerminate(_ hook: @escaping @Sendable () -> Void) {
        let runNow: Bool = state.withLock { state in
            if state.terminated { return true }
            state.hooks.append(hook)
            return false
        }
        if runNow { hook() }
    }
}

/// The handle of a dedicated connection. Call ``close()`` when the call ends (the stream ended, or setup failed).
package final class DedicatedConnection: Sendable {
    package let client: ConnectionProvider.Client
    private let provider: ConnectionProvider
    private let id: UInt64
    private let lifecycle: DedicatedLifecycle

    fileprivate init(provider: ConnectionProvider, id: UInt64, client: ConnectionProvider.Client, lifecycle: DedicatedLifecycle) {
        self.provider = provider
        self.id = id
        self.client = client
        self.lifecycle = lifecycle
    }

    /// Idempotent. Cancels this connection's runTask (stopping every RPC in progress on it) and unregisters it from the provider.
    /// Registered ``onClose(_:)`` hooks run first, once. Also reached by the provider's
    /// `shutdown()`, which terminates the lifecycle directly.
    package func close() {
        provider.deregisterDedicated(id)
        lifecycle.terminate()
    }

    /// Registers a hook that runs once when the connection closes, by ``close()`` or by the
    /// provider's shutdown, outside any lock. A hook registered after the close runs immediately.
    package func onClose(_ hook: @escaping @Sendable () -> Void) {
        lifecycle.onTerminate(hook)
    }

    deinit {
        close()
    }
}

/// A response value that must be told when the dedicated connection carrying it has closed,
/// so a producer suspended on the consumer can be released.
///
/// The handler is stored in the connection's lifecycle, which the provider's registry holds, so it
/// must capture only what it needs (the hand-off) and never the response value itself: the value
/// owns the stream whose release cancels the call, and capturing it would form a retain cycle.
package protocol ConnectionTerminable: Sendable {
    var connectionCloseHandler: @Sendable () -> Void { get }
}
