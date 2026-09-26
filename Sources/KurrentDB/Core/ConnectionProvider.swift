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
import Synchronization

/// 管理兩類連線,依 RPC 是否在 `perform(node:)` **內結束**決定用哪一類:
///
/// - **共用**(``acquire(_:)``):呼叫在 `perform(node:)` 內結束、連線不會逃出作用域的
///   RPC —— 回應為單一訊息的(`UnaryUnary`、`StreamUnary`),以及 `send()` 在回傳前就把
///   stream 排空的 `UnaryStream`(標記 `BufferedStreamResponse`:`Streams.Read`、
///   `Streams.ReadAll`、`Projections.Statistics`、`Users.Details`)。每個 endpoint 共用一條
///   長生命週期的連線,這些呼叫一起分攤該連線的 HTTP/2 stream 額度。
/// - **獨立**(``openDedicated(for:)``):把 stream 帶出 `perform` 的 RPC(訂閱、persistent
///   subscription、`Monitoring.Stats`、`StreamStream`、`BatchAppend`)。可能長期佔住
///   HTTP/2 stream slot,因此每次呼叫獨立一條,不跟任何人共用容量。
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
    package typealias Client = GRPCClient<HTTP2ClientTransport.Posix>

    private struct SharedEntry {
        let generation: UInt64
        let client: Client
        let runTask: Task<Void, Never>
        var retainCount: Int
        var lastUsed: ContinuousClock.Instant
    }

    private struct State {
        var shared: [Endpoint: SharedEntry] = [:]
        var dedicated: [UInt64: Task<Void, Never>] = [:]
        var nextID: UInt64 = 0
        var isShutdown = false
        var createdSharedConnectionCount = 0
        var sweeper: Task<Void, Never>?
    }

    private let settings: ClientSettings
    private let idleTimeout: Duration
    private let state = Mutex(State())

    /// - Parameters:
    ///   - idleTimeout: 共用連線在沒有任何進行中的呼叫後,閒置多久會被回收。
    ///   - sweepInterval: 背景 sweeper 的檢查間隔;傳 `nil` 不啟動 sweeper
    ///     (測試用,改以 ``sweep(now:)`` 手動驅動)。
    package init(
        settings: ClientSettings,
        idleTimeout: Duration = .seconds(3600),
        sweepInterval: Duration? = .seconds(60)
    ) {
        self.settings = settings
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

    /// 取得 `endpoint` 的共用連線,並把它的 retainCount 加一。
    ///
    /// 呼叫端必須在呼叫結束時 ``SharedLease/release()`` —— 在 `perform(node:)` 裡用
    /// `defer { lease.release() }`。查找/發布與 retainCount 遞增在同一個 lock 內完成,
    /// 所以 sweeper 不可能在「查到」與「加一」之間把 entry 移走。
    ///
    /// - Throws: `KurrentError.connectionClosed` 若 provider 已 shutdown;
    ///           transport 建立失敗時則是對應的 `KurrentError`。
    package func acquire(_ endpoint: Endpoint) throws(KurrentError) -> SharedLease {
        if let lease = try retainExisting(endpoint, now: .now) {
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
            if var existing = state.shared[endpoint] {
                existing.retainCount += 1
                existing.lastUsed = now
                state.shared[endpoint] = existing
                return (SharedLease(provider: self, endpoint: endpoint, generation: existing.generation, client: existing.client), false)
            }
            // 在同一個 lock 內建 runTask 並發布完整 entry:任何時刻都不會有一個看得到、
            // 卻沒有可取消 task 的 entry,也不會有逃過登記的 task。
            state.nextID += 1
            let generation = state.nextID
            let runTask = makeSharedRunTask(client: candidate, endpoint: endpoint, generation: generation)
            state.shared[endpoint] = SharedEntry(
                generation: generation,
                client: candidate,
                runTask: runTask,
                retainCount: 1,
                lastUsed: now
            )
            state.createdSharedConnectionCount += 1
            return (SharedLease(provider: self, endpoint: endpoint, generation: generation, client: candidate), true)
        }
        if published {
            logger.debug("[ConnectionProvider] Opened shared connection to \(endpoint.debugDescription)")
        }
        return lease
    }

    private func retainExisting(_ endpoint: Endpoint, now: ContinuousClock.Instant) throws(KurrentError) -> SharedLease? {
        try state.withLock { state throws(KurrentError) -> SharedLease? in
            guard !state.isShutdown else {
                throw KurrentError.connectionClosed
            }
            guard var entry = state.shared[endpoint] else {
                return nil
            }
            entry.retainCount += 1
            entry.lastUsed = now
            state.shared[endpoint] = entry
            return SharedLease(provider: self, endpoint: endpoint, generation: entry.generation, client: entry.client)
        }
    }

    /// 只在 generation 相符時生效。entry 已被移除或已換成新的一代時什麼都不做 ——
    /// 晚到的 release 絕不能動到替換上來的 entry 的計數。
    fileprivate func release(_ endpoint: Endpoint, generation: UInt64) {
        let now = ContinuousClock.now
        state.withLock { state in
            guard var entry = state.shared[endpoint], entry.generation == generation else {
                return
            }
            entry.retainCount = max(0, entry.retainCount - 1)
            entry.lastUsed = now
            state.shared[endpoint] = entry
        }
    }

    private func makeSharedRunTask(client: Client, endpoint: Endpoint, generation: UInt64) -> Task<Void, Never> {
        Task { [weak self] in
            await Self.run(client, endpoint: endpoint)
            // weak self 只在收尾時解析,不跨越上面的 await 提升成強引用。
            self?.sharedRunTaskEnded(endpoint, generation: generation)
        }
    }

    private func sharedRunTaskEnded(_ endpoint: Endpoint, generation: UInt64) {
        let removed = state.withLock { state -> Bool in
            guard state.shared[endpoint]?.generation == generation else {
                return false
            }
            state.shared[endpoint] = nil
            return true
        }
        if removed {
            logger.debug("[ConnectionProvider] Shared connection to \(endpoint.debugDescription) ended; removed from cache")
        }
    }

    /// 移除所有 `retainCount == 0` 且閒置超過 `idleTimeout` 的共用 entry。
    ///
    /// 背景 sweeper 定期以 `.now` 呼叫;測試可注入任意時間點。
    ///
    /// - Returns: 被移除的 entry 數量。
    @discardableResult
    package func sweep(now: ContinuousClock.Instant) -> Int {
        let expired = state.withLock { state -> [(Endpoint, Task<Void, Never>)] in
            let expired = state.shared.filter { _, entry in
                entry.retainCount == 0 && now - entry.lastUsed > idleTimeout
            }
            for endpoint in expired.keys {
                state.shared[endpoint] = nil
            }
            return expired.map { ($0.key, $0.value.runTask) }
        }
        // 只 cancel 當下捕捉到的舊 task;期間若有人 acquire 建了新的一代,不受影響。
        for (endpoint, runTask) in expired {
            logger.debug("[ConnectionProvider] Retiring idle shared connection to \(endpoint.debugDescription)")
            runTask.cancel()
        }
        return expired.count
    }

    // MARK: - Dedicated connections

    /// 為一次 stream 回應的呼叫開一條獨立連線,並向 provider 登記。
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
            // 這個 task 不捕捉 provider,也不捕捉 handle:登記表 → task 這條邊不會形成循環。
            let runTask = Task {
                await Self.run(client, endpoint: endpoint)
            }
            state.dedicated[id] = runTask
            return DedicatedConnection(provider: self, id: id, client: client, runTask: runTask)
        }
    }

    fileprivate func deregisterDedicated(_ id: UInt64) {
        state.withLock { state in
            state.dedicated[id] = nil
        }
    }

    // MARK: - Shutdown

    /// 拒絕之後所有的准入,並取消所有共用連線、已登記的獨立連線與 sweeper。冪等。
    ///
    /// 這是**發起**關閉:返回時連線不保證已經關閉完成。
    package func shutdown() {
        let tasks = state.withLock { state -> [Task<Void, Never>] in
            guard !state.isShutdown else {
                return []
            }
            state.isShutdown = true
            var tasks = state.shared.values.map(\.runTask) + Array(state.dedicated.values)
            if let sweeper = state.sweeper {
                tasks.append(sweeper)
            }
            state.shared.removeAll()
            state.dedicated.removeAll()
            state.sweeper = nil
            return tasks
        }
        for task in tasks {
            task.cancel()
        }
    }

    /// provider 是否已 shutdown。
    package var isShutdown: Bool {
        state.withLock { $0.isShutdown }
    }

    // MARK: - Introspection (tests)

    /// 至今建立過幾條共用連線。只增不減;計的是 `GRPCClient` 的建立次數,不是 TCP 連線或
    /// TLS handshake —— transport 內部的重連不會讓它增加。
    package var createdSharedConnectionCount: Int {
        state.withLock { $0.createdSharedConnectionCount }
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

    /// 測試用:檢視某個 endpoint 目前的共用 entry。
    package func sharedEntrySnapshot(for endpoint: Endpoint) -> SharedEntrySnapshot? {
        state.withLock { state in
            state.shared[endpoint].map {
                SharedEntrySnapshot(generation: $0.generation, retainCount: $0.retainCount, lastUsed: $0.lastUsed)
            }
        }
    }

    /// 測試用:取消某個共用 entry 的 runTask 但**不**移除 entry,藉此走真正的
    /// 「runTask 結束 → identity-checked 移除」路徑。
    package func cancelSharedRunTaskForTesting(_ endpoint: Endpoint) {
        let runTask = state.withLock { $0.shared[endpoint]?.runTask }
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
        let transport: HTTP2ClientTransport.Posix = try withRethrowingError(usage: "ConnectionProvider.makeClient(for:)") {
            try .http2NIOPosix(
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
                }
            )
        }
        return GRPCClient(transport: transport)
    }
}

/// 一次共用連線的使用權。在 `perform(node:)` 內以 `defer { lease.release() }` 釋放。
package final class SharedLease: Sendable {
    package let client: ConnectionProvider.Client
    private let provider: ConnectionProvider
    private let endpoint: Endpoint
    private let generation: UInt64
    private let released = Mutex(false)

    fileprivate init(provider: ConnectionProvider, endpoint: Endpoint, generation: UInt64, client: ConnectionProvider.Client) {
        self.provider = provider
        self.endpoint = endpoint
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
        provider.release(endpoint, generation: generation)
    }

    deinit {
        release()
    }
}

/// 一條獨立連線的 handle。呼叫結束時(stream 終止、setup 失敗)``close()``。
package final class DedicatedConnection: Sendable {
    package let client: ConnectionProvider.Client
    private let provider: ConnectionProvider
    private let id: UInt64
    private let runTask: Task<Void, Never>
    private let closed = Mutex(false)

    fileprivate init(provider: ConnectionProvider, id: UInt64, client: ConnectionProvider.Client, runTask: Task<Void, Never>) {
        self.provider = provider
        self.id = id
        self.client = client
        self.runTask = runTask
    }

    /// 冪等。取消這條連線的 runTask(中止其上所有進行中的 RPC)並從 provider 註銷。
    package func close() {
        let first = closed.withLock { closed in
            defer { closed = true }
            return !closed
        }
        guard first else { return }
        provider.deregisterDedicated(id)
        runTask.cancel()
    }

    deinit {
        close()
    }
}
