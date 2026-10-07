//
//  ConnectionReuseLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml. Verifies connection reuse against
//  a real server: RPCs that finish inside perform (single responses, and the finite streams
//  that read / readAll / projection statistics / user details drain inside send()) share a
//  connection; subscriptions, which carry the stream out of perform, each get their own; and
//  the semantics of shutdown.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Connection reuse (live)", .serialized, .timeLimit(.minutes(3)))
struct ConnectionReuseLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func event(_ type: String = "ConnectionReuse-Test") -> EventData {
        EventData(eventType: type, model: ["Description": "connection reuse"])
    }

    /// 等到條件成立或逾時。只用於等待非同步收尾(cancel 之後 task 何時結束取決於排程)。
    private func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: - Shared connections

    /// 整個改動的核心主張。discovery 的 gossip 探測也走共用連線,所以第一次呼叫後的
    /// 連線數可能不只 1(取決於探測過哪些 seed);要驗證的是之後不再增加。
    @Test("暖機之後再 append 200 次,不會再建立任何共用連線")
    func appendsReuseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")

        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        let warmed = client.selector.connections.createdSharedConnectionCount
        #expect(warmed >= 1)

        for _ in 0 ..< 200 {
            _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        }

        #expect(client.selector.connections.createdSharedConnectionCount == warmed)
        #expect(client.selector.connections.activeDedicatedConnectionCount == 0)
        try await stream.delete()
    }

    @Test("並行的 append 共用同一條連線")
    func concurrentAppendsReuseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")

        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        let warmed = client.selector.connections.createdSharedConnectionCount

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 100 {
                group.addTask {
                    _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
                }
            }
            try await group.waitForAll()
        }

        #expect(client.selector.connections.createdSharedConnectionCount == warmed)
        try await stream.delete()
    }

    // MARK: - Buffered stream responses (shared connection)

    /// A finite stream response (Read) is drained inside send(), so it uses the shared
    /// connection: neither success nor failure opens a dedicated one, and a failed read must
    /// not break the shared connection — the following append has to complete on the same one.
    @Test("成功與失敗的 read 都走共用連線,且不影響之後的 append")
    func finiteReadsUseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event(), event()]) { $0.expectedRevision = .any }
        let warmed = client.selector.connections.createdSharedConnectionCount

        var count = 0
        for try await _ in try await stream.read() {
            count += 1
        }
        #expect(count == 2)

        let missing = client.streams(specified: "ConnectionReuse-missing-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            for try await _ in try await missing.read() {}
        }

        // A read never creates a dedicated connection. createdDedicatedConnectionCount is
        // monotonic, which is what distinguishes "opened and closed" from "never opened".
        #expect(client.selector.connections.createdDedicatedConnectionCount == 0)
        #expect(client.selector.connections.activeDedicatedConnectionCount == 0)
        #expect(client.selector.connections.createdSharedConnectionCount == warmed)

        // After a failed read the shared connection must still work.
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        #expect(client.selector.connections.createdSharedConnectionCount == warmed)
        try await stream.delete()
    }

    @Test("readAll、projection statistics、user details 都走共用連線")
    func otherBufferedUsecasesUseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        let warmed = client.selector.connections.createdSharedConnectionCount

        for _ in 0 ..< 20 {
            for try await _ in try await client.allStreams.read(configure: { $0.limit = 5 }) {}
        }
        for _ in 0 ..< 20 {
            _ = try await client.projections(of: .anyContinuous).list()
        }
        for _ in 0 ..< 20 {
            for try await _ in try await client.user("admin").details() {}
        }

        #expect(client.selector.connections.createdSharedConnectionCount == warmed)
        #expect(client.selector.connections.createdDedicatedConnectionCount == 0)
        #expect(client.selector.connections.activeDedicatedConnectionCount == 0)
        try await stream.delete()
    }

    /// Beyond the server's per-connection concurrent-stream limit, extra reads queue on the
    /// client instead of failing, and do not starve appends on the same connection. This is
    /// the tradeoff #143 accepts; pin it here.
    ///
    /// The load of this test has made a CI cluster elect a new leader mid-run (runs 37428841325
    /// and 37434185712: 2111 → 2112 while the reads were in flight; the election itself is now
    /// prevented by `KURRENTDB_GOSSIP_TIMEOUT_MS` in server/vars.env) and has made single calls
    /// hit a transient node failure (run 37563292652). Both make the client rediscover, which
    /// legitimately opens connections that have nothing to do with the reads. What the reads must
    /// never do is replace the shared entry of the node that served them; that is pinned through
    /// the entry's generation, which only changes when a new connection is created for that endpoint.
    ///
    /// What matters is the number of concurrent reads (150, above the 100-stream limit), not their
    /// size. With 200 events per read the 30,000 storage reads saturated the leader on a shared
    /// runner (run 37591445038: reads queued 1.6–3.6 s on the server's reader bus) until the
    /// concurrent append failed server-side with "Commit phase timeout" on both attempts. 20 events
    /// per read keep the client-side queueing this test is about while cutting the server load tenfold.
    @Test("150 個並行 read 全部完成,期間的 append 也完成,且不替換服務它們的共用連線")
    func manyConcurrentReadsDoNotStarveAppends() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: (0 ..< 20).map { _ in event() }) { $0.expectedRevision = .any }
        let endpoint = try #require(await client.selector.selectedNode?.endpoint)
        let generation = try #require(client.selector.connections.sharedEntrySnapshot(for: endpoint)?.generation)

        let readCounts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 150 {
                group.addTask {
                    var n = 0
                    for try await _ in try await stream.read() { n += 1 }
                    return n
                }
            }
            // An append issued while reads are queued must still complete.
            group.addTask {
                _ = try await stream.append(events: [self.event()]) { $0.expectedRevision = .any }
                return -1
            }
            var counts: [Int] = []
            for try await n in group { counts.append(n) }
            return counts
        }

        #expect(readCounts.filter { $0 >= 20 }.count == 150)
        #expect(readCounts.contains(-1))
        // Only the serving endpoint's entry is pinned. The total count is not: any transient
        // node-failure retry rediscovers through the first reachable seed, which opens a gossip
        // connection to a node that is not the leader (+1, leader unchanged — CI run 37563292652),
        // and a leader election adds the new leader's connection on top. Neither is a read
        // opening a connection.
        #expect(client.selector.connections.sharedEntrySnapshot(for: endpoint)?.generation == generation)
        #expect(client.selector.connections.activeDedicatedConnectionCount == 0)
        try await stream.delete()
    }

    /// A buffered read's RPC runs entirely inside send(), so "mid-drain" means the window in
    /// which send() is still draining. Its observable signal is the endpoint's retainCount
    /// rising to baseline + 1 (lease taken, not yet returned by defer): wait for it before
    /// cancelling, and require the reader to end in failure to prove the cancellation
    /// interrupted an in-flight RPC. Afterwards retainCount must return to baseline — "the next
    /// append succeeds" cannot catch a leaked retain (acquire would simply reuse that entry).
    @Test("取消排空中的 read 會還掉 lease,共用連線之後仍可用")
    func cancellingReadMidDrainReleasesLease() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        for _ in 0 ..< 2 {
            _ = try await stream.append(events: (0 ..< 5000).map { _ in event() }) { $0.expectedRevision = .any }
        }
        let warmed = client.selector.connections.createdSharedConnectionCount
        let endpoint = try #require(await client.selector.selectedNode?.endpoint)
        let baseline = try #require(client.selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount)

        let reader = Task {
            for try await _ in try await stream.read() {}
        }
        var sawLeaseHeld = false
        for _ in 0 ..< 2000 {
            if client.selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount == baseline + 1 {
                sawLeaseHeld = true
                break
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        try #require(sawLeaseHeld, "read finished before the held lease was observed; enlarge the stream")
        reader.cancel()
        let result = await reader.result
        #expect(throws: (any Error).self) { try result.get() }

        #expect(client.selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount == baseline)

        // If the shared connection were broken, the next append would fail or open a new one.
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        #expect(client.selector.connections.createdSharedConnectionCount == warmed)
        #expect(client.selector.connections.createdDedicatedConnectionCount == 0)
        try await stream.delete()
    }

    @Test("shutdown 期間的 read 會在有限時間內結束,不會掛住")
    func shutdownDuringReadEndsIteration() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: (0 ..< 2000).map { _ in event() }) { $0.expectedRevision = .any }

        let reader = Task {
            do {
                for try await _ in try await stream.read() {}
            } catch {}
        }
        try await Task.sleep(for: .milliseconds(5))
        try client.shutdown()

        let ended = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await reader.value; return true }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(ended)
    }

    // MARK: - Dedicated connections

    @Test("取消一個訂閱,不影響同一個 client 上的其他訂閱與 unary 呼叫")
    func cancellingOneSubscriptionLeavesOthersWorking() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")

        let cancelled = try await stream.subscribe()
        let kept = try await stream.subscribe()
        #expect(client.selector.connections.activeDedicatedConnectionCount == 2)

        cancelled.cancel()
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 1 })

        let appended = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        let received = try await kept.events.first { _ in true }
        #expect(received?.record.revision == appended.currentRevision)

        kept.cancel()
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        try await stream.delete()
    }

    /// helper 在區域內建立 client 並只回傳訂閱:client 與 facade 都被釋放後,訂閱仍要可用。
    @Test("helper 回傳的訂閱在 client 與 facade 被釋放後仍然可用")
    func returnedSubscriptionOutlivesClient() async throws {
        let streamName = "ConnectionReuse-\(UUID().uuidString)"

        func makeSubscription() async throws -> Streams<SpecifiedStream>.Subscription {
            let local = KurrentDBClient(settings: settings)
            return try await local.streams(specified: streamName).subscribe()
        }
        let subscription = try await makeSubscription()

        let writer = KurrentDBClient(settings: settings)
        defer { try? writer.shutdown() }
        let appended = try await writer.streams(specified: streamName)
            .append(events: [event()]) { $0.expectedRevision = .any }

        let received = try await subscription.events.first { _ in true }
        #expect(received?.record.revision == appended.currentRevision)

        subscription.cancel()
        try await writer.streams(specified: streamName).delete()
    }

    /// 每個訂閱各自一條連線,所以伺服器單一連線的並行 stream 上限不會讓它們互相排隊。
    @Test("150 個並行訂閱全部收到確認")
    func manyConcurrentSubscriptionsAreConfirmed() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")

        let subscriptions = try await withThrowingTaskGroup(of: Streams<SpecifiedStream>.Subscription.self) { group in
            for _ in 0 ..< 150 {
                group.addTask { try await stream.subscribe() }
            }
            var all: [Streams<SpecifiedStream>.Subscription] = []
            for try await subscription in group {
                all.append(subscription)
            }
            return all
        }

        #expect(subscriptions.count == 150)
        #expect(subscriptions.allSatisfy { $0.subscriptionId != nil })

        // 150 個訂閱都開著的時候,unary 呼叫仍然能完成。
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }

        subscriptions.forEach { $0.cancel() }
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        try await stream.delete()
    }

    // MARK: - Shutdown

    @Test("shutdown 會結束進行中的訂閱,並拒絕之後所有的呼叫(node 仍在快取中)")
    func shutdownEndsSubscriptionsAndRejectsCalls() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }   // node 進入快取
        let subscription = try await stream.subscribe()

        let consumer = Task {
            do {
                for try await _ in subscription.events {}
            } catch {}
        }

        try client.shutdown()

        // 訂閱必須在有限時間內結束,而不是永遠掛著。
        let ended = await withTaskGroup(of: Bool.self) { group in
            group.addTask { await consumer.value; return true }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        #expect(ended)
        consumer.cancel()

        await #expect(throws: KurrentError.connectionClosed) {
            _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        }
        await #expect(throws: KurrentError.connectionClosed) {
            _ = try await stream.subscribe()
        }
        await #expect(throws: KurrentError.connectionClosed) {
            for try await _ in try await stream.read() {}
        }
        #expect(client.selector.connections.activeDedicatedConnectionCount == 0)
    }
}
