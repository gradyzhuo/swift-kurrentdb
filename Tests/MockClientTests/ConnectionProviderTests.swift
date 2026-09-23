//
//  ConnectionProviderTests.swift
//  swift-kurrentdb
//
//  不需要伺服器:全部指向本機沒有在監聽的特權 port(127.0.0.1:1、:2),連線會立即被
//  拒絕(ECONNREFUSED)。刻意不用 TEST-NET 位址(192.0.2.x):那種位址不回應 SYN,
//  已經開始連線的 runConnections() 要等到 TCP connect 逾時(約 10 秒)才會對 cancel
//  有反應,會讓「cancel 後 runTask 結束」的斷言變得與時序相關。這些測試仍會實際發出
//  連線嘗試(與伺服器無關,但不是完全沒有網路活動)。
//
//  sweeper 一律關閉(sweepInterval: nil),改用 sweep(now:) 以注入的時間點驅動,
//  讓回收相關的斷言與實際時間無關。每個測試結束都 shutdown(),避免在整個測試程序
//  裡累積對不可達目標無限期掛著的 runConnections()。
//

import Testing
@testable import KurrentDB

@Suite("ConnectionProvider", .serialized, .timeLimit(.minutes(1)))
struct ConnectionProviderTests {
    private static let endpointA = Endpoint(host: "127.0.0.1", port: 1)
    private static let endpointB = Endpoint(host: "127.0.0.1", port: 2)

    private func makeProvider(idleTimeout: Duration = .seconds(3600)) -> ConnectionProvider {
        ConnectionProvider(settings: .localhost(), idleTimeout: idleTimeout, sweepInterval: nil)
    }

    /// 等到條件成立或逾時。只用於等待真實的 task 收尾(cancel 之後 runTask 何時結束
    /// 取決於排程),不用於任何時間相關的業務斷言。
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0 ..< 200 {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    // MARK: - Shared: reuse

    @Test("同一個 endpoint 取兩次會拿到同一條連線")
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

    @Test("不同 endpoint 各自一條連線")
    func separateConnectionsPerEndpoint() throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let a = try provider.acquire(Self.endpointA)
        let b = try provider.acquire(Self.endpointB)
        defer { a.release(); b.release() }

        #expect(a.client !== b.client)
        #expect(provider.createdSharedConnectionCount == 2)
    }

    /// 整個改動的核心主張:高併發下同一個 endpoint 只建立一條共用連線。
    /// 未命中的並行呼叫會各自在 lock 外建構,但只有一個能發布;其餘丟棄自己的。
    @Test("100 個並行 acquire 打同一個 endpoint 只建立一條連線")
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

    @Test("release 只生效一次;deinit 保底只釋放一次")
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
            _ = try provider.acquire(Self.endpointA)   // 立即被釋放 → deinit 保底
        }
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.retainCount == 1)
    }

    /// Codex 第三輪的 P1:A 被移除後,同 endpoint 換成 B;A 晚到的 release 不能動到 B。
    @Test("舊一代的 release 不會影響替換上來的新 entry")
    func staleReleaseDoesNotTouchReplacement() async throws {
        let provider = makeProvider()
        defer { provider.shutdown() }

        let leaseA = try provider.acquire(Self.endpointA)
        let generationA = try #require(provider.sharedEntrySnapshot(for: Self.endpointA)).generation

        // 走真正的「runTask 結束 → identity-checked 移除」路徑。
        provider.cancelSharedRunTaskForTesting(Self.endpointA)
        #expect(try await eventually { provider.sharedEntrySnapshot(for: Self.endpointA) == nil })

        let leaseB = try provider.acquire(Self.endpointA)
        let before = try #require(provider.sharedEntrySnapshot(for: Self.endpointA))
        #expect(before.generation != generationA)
        #expect(before.retainCount == 1)

        leaseA.release()

        let after = try #require(provider.sharedEntrySnapshot(for: Self.endpointA))
        #expect(after == before)

        // B 仍在使用中,任何時間點的 sweep 都不能移除它。
        #expect(provider.sweep(now: .now + .seconds(365 * 24 * 3600)) == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA)?.generation == before.generation)

        leaseB.release()
    }

    @Test("被取消而結束的 runTask 會移除 entry,下一次 acquire 建新的一代")
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

    @Test("sweep 只移除沒有使用中且閒置超過 TTL 的 entry")
    func sweepRemovesOnlyIdleExpiredEntries() throws {
        let provider = makeProvider(idleTimeout: .seconds(3600))
        defer { provider.shutdown() }

        let inUse = try provider.acquire(Self.endpointA)
        defer { inUse.release() }
        let idle = try provider.acquire(Self.endpointB)
        idle.release()
        let releasedAt = try #require(provider.sharedEntrySnapshot(for: Self.endpointB)).lastUsed

        // 還沒超過 TTL:都不動。
        #expect(provider.sweep(now: releasedAt + .seconds(3599)) == 0)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointB) != nil)

        // 超過 TTL:只移除閒置的那個;使用中的 A 不論多久都留著。
        #expect(provider.sweep(now: releasedAt + .seconds(3601)) == 1)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointB) == nil)
        #expect(provider.sharedEntrySnapshot(for: Self.endpointA) != nil)
    }

    @Test("sweep 前剛被 acquire 的 entry 不會被移除")
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

    @Test("被 sweep 回收的 endpoint,下一次 acquire 會拿到新的連線")
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

    // MARK: - Dedicated

    @Test("獨立連線每次都是新的,close 後註銷且 close 是冪等的")
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

    /// helper 回傳的訂閱在 client/facade/Node 全部釋放後仍要可用:獨立連線的 handle
    /// 必須讓 provider 活著,直到它自己 close。
    @Test("獨立連線的 handle 讓 provider 活到它 close 為止")
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

    // MARK: - Shutdown

    @Test("shutdown 之後共用與獨立連線的准入都會被拒絕")
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

        // shutdown 之後的 release / close 都是 no-op,不會出錯。
        lease.release()
        dedicated.close()
    }

    @Test("shutdown 是冪等的")
    func shutdownIsIdempotent() throws {
        let provider = makeProvider()
        try provider.acquire(Self.endpointA).release()

        provider.shutdown()
        provider.shutdown()

        #expect(provider.createdSharedConnectionCount == 1)
    }

    /// runTask 可能在 shutdown 取消它時都還沒被排程;取消後它仍必須正常結束,
    /// 且不能把已經關閉的 provider 恢復。
    @Test("在 runTask 開始前 shutdown,連線仍會收尾且 provider 保持關閉")
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

    @Test("與 shutdown 並行的 acquire / openDedicated 不是被拒絕,就是被納入 shutdown")
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
            // 不論誰先誰後,shutdown 之後都不能殘留任何 entry 或登記。
            #expect(provider.sharedEntrySnapshot(for: Self.endpointA) == nil)
            #expect(provider.activeDedicatedConnectionCount == 0)
        }
    }
}

@Suite("KurrentDBClient shutdown", .serialized, .timeLimit(.minutes(1)))
struct KurrentDBClientShutdownTests {
    @Test("public shutdown 是冪等的,並關閉連線來源")
    func shutdownIsIdempotentAndClosesProvider() throws {
        let client = KurrentDBClient(settings: .localhost())

        try client.shutdown()
        try client.shutdown()

        #expect(client.selector.connections.isShutdown)
    }

    /// 不論 node 快取是否過期,shutdown 之後 select() 都要立刻回報 connectionClosed,
    /// 而不是進入 discovery 重試、最後回報「找不到 node」。
    @Test("shutdown 之後 select() 立即拋 connectionClosed")
    func selectAfterShutdownThrowsConnectionClosed() async throws {
        let client = KurrentDBClient(settings: .localhost())
        try client.shutdown()

        await #expect(throws: KurrentError.connectionClosed) {
            try await client.selector.select()
        }
    }
}
