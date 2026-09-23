//
//  ConnectionReuseLiveTests.swift
//  swift-kurrentdb
//
//  需要 server/docker-compose.yaml 的 3 節點 cluster。驗證連線復用在真實伺服器上的行為:
//  單一回應的 RPC 共用連線、stream 回應的 RPC 各自獨立,以及 shutdown 的語意。
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

    // MARK: - Dedicated connections

    /// 有限的 stream 回應(Read)在 send() 內就完成收尾;成功與失敗兩條路徑都要把獨立連線還掉。
    @Test("成功與失敗的 read 都會關閉自己的獨立連線")
    func finiteReadsCloseDedicatedConnections() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event(), event()]) { $0.expectedRevision = .any }

        var count = 0
        for try await _ in try await stream.read() {
            count += 1
        }
        #expect(count == 2)

        let missing = client.streams(specified: "ConnectionReuse-missing-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            for try await _ in try await missing.read() {}
        }

        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        try await stream.delete()
    }

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
