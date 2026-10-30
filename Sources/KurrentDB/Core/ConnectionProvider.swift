//
//  ConnectionProvider.swift
//  swift-kurrentdb
//
//  KurrentDBClient 所有 gRPC 連線的准入與生命週期管理點。
//
//  取名 ConnectionProvider 而不是 ConnectionPool,是為了避開 Sources/KurrentDBPool/。
//  那個 KurrentDBPool 池化的是「彼此不相干的獨立資料庫」(測試隔離用),假設跟這裡
//  正好相反 —— 見 tasks/todo-kurrentdb-pool.md。名字撞車會害人讀錯。
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
/// ## 為什麼是 Mutex 而不是 actor
///
/// `deinit` 與既有的同步 `KurrentDBClient.shutdown()` 都不能 `await`,而這裡需要的每一個
/// 動作 —— 發布 entry、建立 Task、`Task.cancel()` —— 都是同步的。昂貴的部分(建 transport,
/// TLS 會同步建構 `NIOSSLContext`、可能讀憑證檔)一律在 lock 外完成。
///
/// ## 為什麼收尾一律只 cancel
///
/// `GRPCClient.beginGracefulShutdown()` 在 client 仍是 `.notStarted` 時會直接跳到
/// `.stopped`,且不通知 transport;之後 `runConnections()` 拋 `clientIsStopped`。而對長
/// 生命週期的 stream,graceful shutdown 會等它結束 —— 永遠等不到。取消執行
/// `runConnections()` 的 task 則會中止所有進行中的 RPC,且呼叫本身正常返回
/// (見 `GRPCClientLifecycleCharacterizationTests`)。
///
/// 注意 cancel 不一定**立即**生效:對一個不回應 SYN 的位址,已經開始連線的
/// `runConnections()` 要等到這次 TCP connect 逾時(約 10 秒)才會返回;被拒絕
/// (ECONNREFUSED)或已連上的連線則會立即返回。所以 sweep 與 shutdown 一律先把 entry
/// 從表中移除、再 cancel —— 沒有人能拿到一個正在收尾的 client。
///
/// ## 共用連線的回收
///
/// 不依錯誤逐出:`.deadlineExceeded`、伺服器回的 UNAVAILABLE、`.notLeaderException`
/// 都不代表 transport 死了,而暫時性故障 transport 自己會重連。entry 只在兩種情況被移除:
/// 它的 runTask 真的結束了,或是背景 sweeper 發現它 `retainCount == 0` 且閒置超過
/// `idleTimeout`。後者是必要的 —— transport 的 `maxIdleTime` 只關 socket,不會結束
/// runTask;gossip 回報的舊 endpoint 與死掉的 seed 若不回收,會在背景永遠重連。
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
    ///   - idleTimeout: 共用連線在沒有任何進行中的呼叫後,閒置多久會被回收。
    ///   - sweepInterval: 背景 sweeper 的檢查間隔;傳 `nil` 不啟動 sweeper
    ///     (測試用,改以 ``sweep(now:)`` 手動驅動)。
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
        // weak:sweeper 不能讓 provider 活著。強引用只存活到單次 sweep 結束,
        // 不會跨越下一次 sleep。provider 若在這一次強引用釋放時 deinit,deinit 只會
        // cancel 這個 task,不會等它 —— 所以不會自我死結。
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

    /// 取得 `endpoint` 上 `purpose` 那條共用連線,並把它的 retainCount 加一。
    ///
    /// 呼叫端必須在呼叫結束時 ``SharedLease/release()`` —— 在 `perform(node:)` 裡用
    /// `defer { lease.release() }`。查找/發布與 retainCount 遞增在同一個 lock 內完成,
    /// 所以 sweeper 不可能在「查到」與「加一」之間把 entry 移走。
    ///
    /// - Parameter purpose: `.main` (the default) for every call that ends inside `perform`;
    ///   `.read` for a lazy read, which holds its stream for as long as the caller iterates.
    ///   Each purpose is its own connection, entry, generation and idle clock.
    /// - Throws: `KurrentError.connectionClosed` 若 provider 已 shutdown;
    ///           transport 建立失敗時則是對應的 `KurrentError`。
    package func acquire(_ endpoint: Endpoint, purpose: ConnectionPurpose = .main) throws(KurrentError) -> SharedLease {
        let key = SharedKey(endpoint: endpoint, purpose: purpose)
        if let lease = try retainExisting(key, now: .now) {
            return lease
        }

        // 未命中:在 lock 外建構(TLS 很貴),再進 lock 發布。
        let candidate = try makeClient(for: endpoint)
        let (lease, published) = try state.withLock { state throws(KurrentError) -> (SharedLease, Bool) in
            guard !state.isShutdown else {
                throw KurrentError.connectionClosed
            }
            let now = ContinuousClock.now
            // 別人在我們建構期間先發布了:用它的,丟掉我們的(從未 run 過,直接釋放即可)。
            if var existing = state.shared[key] {
                existing.retainCount += 1
                existing.lastUsed = now
                state.shared[key] = existing
                return (SharedLease(provider: self, endpoint: endpoint, purpose: purpose, generation: existing.generation, client: existing.client), false)
            }
            // 在同一個 lock 內建 runTask 並發布完整 entry:任何時刻都不會有一個看得到、
            // 卻沒有可取消 task 的 entry,也不會有逃過登記的 task。
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

    /// 只在 generation 相符時生效。entry 已被移除或已換成新的一代時什麼都不做 ——
    /// 晚到的 release 絕不能動到替換上來的 entry 的計數。
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
            // weak self 只在收尾時解析,不跨越上面的 await 提升成強引用。
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

    /// 移除所有 `retainCount == 0` 且閒置超過 `idleTimeout` 的共用 entry,兩種 purpose 都算。
    ///
    /// 背景 sweeper 定期以 `.now` 呼叫;測試可注入任意時間點。
    ///
    /// - Returns: 被移除的 entry 數量。
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
        // 只 cancel 當下捕捉到的舊 task;期間若有人 acquire 建了新的一代,不受影響。
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
    /// 登記是 atomic 的:與 ``shutdown()`` 競爭時,不是被拒絕,就是被納入 shutdown 的取消集合。
    /// 回傳的 handle 會強引用 provider 直到 ``DedicatedConnection/close()``,所以一個被
    /// helper 回傳出去的訂閱,不會因為 client 或 facade 被釋放而中斷。
    ///
    /// - Throws: `KurrentError.connectionClosed` 若 provider 已 shutdown。
    package func openDedicated(for endpoint: Endpoint) throws(KurrentError) -> DedicatedConnection {
        // 先檢查一次:已 shutdown 就不必建 transport,且呼叫端拿到的一定是 connectionClosed,
        // 而不是建構失敗的錯誤。發布前的第二次檢查仍然需要,用來涵蓋建構期間發生的 shutdown。
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
            // 這個 task 不捕捉 provider,也不捕捉 handle:登記表 → task 這條邊不會形成循環。
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

    /// 拒絕之後所有的准入,並取消所有共用連線(兩種 purpose)、已登記的獨立連線與 sweeper。冪等。
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
    /// 這是**發起**關閉:返回時連線不保證已經關閉完成。
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

    /// provider 是否已 shutdown。
    package var isShutdown: Bool {
        state.withLock { $0.isShutdown }
    }

    // MARK: - Introspection (tests)

    /// 至今建立過幾條 `.main` 共用連線。只增不減;計的是 `GRPCClient` 的建立次數,不是 TCP 連線或
    /// TLS handshake —— transport 內部的重連不會讓它增加。`.read` 連線另計於
    /// ``createdReadConnectionCount``。
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

    /// 目前登記中的獨立連線數量。
    package var activeDedicatedConnectionCount: Int {
        state.withLock { $0.dedicated.count }
    }

    package struct SharedEntrySnapshot: Equatable, Sendable {
        package let generation: UInt64
        package let retainCount: Int
        package let lastUsed: ContinuousClock.Instant
    }

    /// 測試用:檢視某個 endpoint 目前的 `.main` 共用 entry。
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

    /// 測試用:取消某個共用 entry 的 runTask 但**不**移除 entry,藉此走真正的
    /// 「runTask 結束 → identity-checked 移除」路徑。
    package func cancelSharedRunTaskForTesting(_ endpoint: Endpoint, purpose: ConnectionPurpose = .main) {
        let runTask = state.withLock { $0.shared[SharedKey(endpoint: endpoint, purpose: purpose)]?.runTask }
        runTask?.cancel()
    }

    // MARK: - Private

    private static func run(_ client: Client, endpoint: Endpoint) async {
        do {
            try await client.runConnections()
        } catch let error as RuntimeError where error.code == .clientIsStopped {
            // 正常收尾:client 在 task 開始前就被停掉了。
        } catch {
            // 過去五處呼叫點把這個錯誤靜默吞掉,連線故障因此無從診斷。
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
                    // ClientSettings.keepAlive 過去被解析進來卻從未傳給 transport(transport
                    // 預設不開 keepalive)。allowWithoutCalls: false —— 不引入新的閒置 ping
                    // 行為;閒置的共用連線交給 transport 的 maxIdleTime 與本類別的 sweeper。
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

/// 一次共用連線的使用權。在 `perform(node:)` 內以 `defer { lease.release() }` 釋放。
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

    /// 只有第一次呼叫有效。
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

/// 一條獨立連線的 handle。呼叫結束時(stream 終止、setup 失敗)``close()``。
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

    /// 冪等。取消這條連線的 runTask(中止其上所有進行中的 RPC)並從 provider 註銷。
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
