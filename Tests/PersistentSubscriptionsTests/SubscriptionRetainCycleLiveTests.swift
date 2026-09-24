//
//  SubscriptionRetainCycleLiveTests.swift
//  swift-kurrentdb
//
//  Issue #127 的回歸測試,全部走真實的 subscribe() → Read.send 路徑(不直接建構
//  Subscription —— 那樣繞過了會強持有它的 read task,正是 SubscriptionLifecycleTests
//  抓不到這個 cycle 的原因)。需要 server/docker-compose.yaml 的 3 節點 cluster。
//
//  兩個觀測點:
//  - client 端:ConnectionProvider 登記中的獨立連線數(persistent subscription 是
//    stream 回應的 RPC,每個訂閱各一條)。
//  - 伺服器端:getInfo().connections —— 伺服器認為還連著的 consumer 數。
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Persistent subscription retain cycle (#127, live)", .serialized, .timeLimit(.minutes(2)))
struct SubscriptionRetainCycleLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func event(_ tag: String) -> EventData {
        EventData(eventType: "RetainCycle-\(tag)", model: ["tag": tag])
    }

    /// 等到條件成立或逾時。只用於等待非同步收尾(釋放 → onTermination → cancel →
    /// 伺服器察覺斷線,每一步的時機都取決於排程與網路)。
    private func eventually(timeout: Duration = .seconds(15), _ condition: () async throws -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .milliseconds(100))
        }
        return try await condition()
    }

    @Test("丟棄從未 iterate 的 handle,會關閉連線(指定 stream)")
    func droppingUniteratedSpecifiedSubscriptionClosesConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let group = "retain-cycle-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(stream: "RetainCycle-\(UUID().uuidString)", group: group)
        try await persistent.create()

        do {
            // 刻意不 iterate events,離開這個 scope 後就不再有人持有 handle。
            _ = try await persistent.subscribe()
        }

        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        #expect(try await eventually { try await persistent.getInfo().connections.isEmpty })

        try await persistent.delete()
    }

    @Test("丟棄從未 iterate 的 handle,會關閉連線($all)")
    func droppingUniteratedAllStreamSubscriptionClosesConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let group = "retain-cycle-all-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(of: .allStreams(group: group))
        try await persistent.create()

        do {
            _ = try await persistent.subscribe()
        }

        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        #expect(try await eventually { try await persistent.getInfo().connections.isEmpty })

        try await persistent.delete()
    }

    /// issue 特別要求的情境:只拿 events 來 iterate、不持有 handle。修掉 cycle 之後
    /// handle 在拿到 events 後就會被釋放,事件不能因此在途中被丟掉;events 本身釋放時收尾。
    @Test("只持有 events、不持有 handle 時,事件不會在途中遺失")
    func iteratingEventsWithoutHoldingHandleDeliversEverything() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let streamName = "RetainCycle-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(stream: streamName, group: "retain-cycle-\(UUID().uuidString)")
        try await persistent.create()

        let expected = (0 ..< 5).map { "e\($0)" }
        var received: [String] = []
        do {
            // 只留下 events;subscribe() 回傳的 handle 本身沒有任何人持有。
            let events = try await persistent.subscribe().events

            for tag in expected {
                _ = try await client.streams(specified: streamName).append(events: [event(tag)]) {
                    $0.expectedRevision = .any
                }
            }

            for try await result in events {
                received.append(result.event.record.eventType)
                if received.count == expected.count { break }
            }
        }
        #expect(received == expected.map { "RetainCycle-\($0)" })

        // events 離開 scope 後,連線關閉。(單純 break 不會 —— 見 Subscription 的文件。)
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })

        try await client.streams(specified: streamName).delete()
        try await persistent.delete()
    }

    /// 一般用法:持有 handle、iterate、ack、跳出迴圈,handle 釋放時收尾。
    @Test("持有 handle 的一般用法照常運作,handle 釋放時收尾")
    func holdingHandleStillWorksAndTearsDown() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let streamName = "RetainCycle-\(UUID().uuidString)"
        let persistent = client.persistentSubscriptions(stream: streamName, group: "retain-cycle-\(UUID().uuidString)")
        try await persistent.create()

        var receivedType: String?
        do {
            let subscription = try await persistent.subscribe()
            _ = try await client.streams(specified: streamName).append(events: [event("held")]) {
                $0.expectedRevision = .any
            }

            for try await result in subscription.events {
                try await subscription.ack(readEvents: result.event)
                receivedType = result.event.record.eventType
                break
            }

            // 還持有 handle 時,break 不會關閉連線。
            #expect(client.selector.connections.activeDedicatedConnectionCount == 1)
        }
        #expect(receivedType == "RetainCycle-held")

        // handle 離開 scope 後,連線關閉。
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        #expect(try await eventually { try await persistent.getInfo().connections.isEmpty })

        try await client.streams(specified: streamName).delete()
        try await persistent.delete()
    }
}
