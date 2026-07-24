//
//  PersistentSubscriptionAdvancedTests.swift
//  swift-kurrentdb
//
//  Integration tests for persistent subscription NACK, getInfo, update,
//  and list operations. Requires a running KurrentDB instance.
//

import Foundation
@testable import KurrentDB
import Testing

// `.timeLimit` 作為終極 backstop:任何測試(尤其 testReplayParked 等 redelivery 的
// `subscription2.events` 迴圈)若因非預期原因無限等待,會在此上限失敗,而非把 CI 卡到被砍。
// 這是維運上限,非時序斷言;健康單一測試遠低於此。
@Suite("Persistent Subscription Advanced Tests", .serialized, .timeLimit(.minutes(2)))
struct PersistentSubscriptionAdvancedTests: Sendable {
    let settings: ClientSettings
    let groupName: String

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
        groupName = "test-ps-advanced-\(UUID().uuidString)"
    }

    // MARK: - NACK

    @Test("NACK with park action sends event to parked queue without error")
    func testNackWithPark() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()
        let subscription = try await ps.subscribe()

        try await client.streams(specified: streamName)
            .append(
                events: [EventData(eventType: "PS-Nack-Event", model: ["x": 1])]
            )

        var received: PersistentSubscription.EventResult?
        for try await result in subscription.events {
            received = result
            try await subscription.nack(readEvents: result.event, action: .park, reason: "unit-test-park")
            break
        }

        #expect(received != nil)
        try await ps.delete()
        try await client.streams(specified: streamName).delete()
    }

    @Test("NACK with retry action re-delivers the event")
    func testNackWithRetry() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()
        let subscription = try await ps.subscribe()

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "PS-NackRetry-Event", model: ["x": 2])]) {
                $0.expectedRevision = .any
            }

        // Receive once and NACK with retry, then ACK on retry delivery
        var deliveries = 0
        for try await result in subscription.events {
            deliveries += 1
            if deliveries == 1 {
                try await subscription.nack(readEvents: result.event, action: .retry, reason: "unit-test-retry")
            } else {
                try await subscription.ack(readEvents: result.event)
                break
            }
        }

        #expect(deliveries == 2)
        try await ps.delete()
        try await client.streams(specified: streamName).delete()
    }

    // MARK: - getInfo

    @Test("getInfo returns correct group name and event source")
    func testGetInfo() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()

        let info = try await ps.getInfo()
        #expect(info.groupName == groupName)
        #expect(info.eventSource == streamName)

        try await ps.delete()
    }

    @Test("getInfo for $all subscription returns '$all' event source")
    func testGetInfoAllStream() async throws {
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(of: .allStreams(group: groupName))

        try await ps.create()

        let info = try await ps.getInfo()
        #expect(info.groupName == groupName)
        #expect(info.eventSource == "$all")

        try await ps.delete()
    }

    // MARK: - Update

    @Test("Update subscription settings does not throw")
    func testUpdateSubscription() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)

        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)        
        try await ps.create()
        
        try await ps.update { $0.settings.maxRetryCount = 5 }

        // getInfo to confirm the setting was applied
        let info = try await ps.getInfo()
        #expect(info.maxRetryCount == 5)

        try await ps.delete()
    }

    // MARK: - List

    @Test("List subscriptions for a stream returns created subscription")
    func testListSubscriptionsForStream() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()

        let subscriptions = try await client.persistentSubscriptions(filterStream: streamName).list()
        #expect(subscriptions.contains { $0.groupName == groupName })

        try await ps.delete()
    }

    @Test("Delete subscription removes it from the list")
    func testDeleteSubscriptionRemovesFromList() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create()
        try await ps.delete()

        let subscriptions = try await client.persistentSubscriptions(filterStream: streamName).list()
        #expect(!subscriptions.contains { $0.groupName == groupName })
    }

    // MARK: - Replay parked

    @Test("Replay parked messages re-delivers parked events")
    func testReplayParked() async throws {
        let streamName = UUID().uuidString
        let client = KurrentDBClient(settings: settings)
        let ps = client.persistentSubscriptions(stream: streamName, group: groupName)

        try await ps.create{
            $0.revision = .start
            $0.settings.messageTimeout = .ms(6000)
        }
        let subscription = try await ps.subscribe()

        try await client.streams(specified: streamName)
            .append(events: [EventData(eventType: "PS-ReplayParked", model: ["x": 3])]) {
                $0.expectedRevision = .any
            }

        // Park the event
        for try await result in subscription.events {
            try await subscription.nack(readEvents: result.event, action: .park, reason: "park-for-replay-test")
            break
        }

        // nack(park) 是射後不理:enqueue 後即返回,伺服器尚未 commit park。
        // 必須等 parkedMessageCount 反映 park 完成再觸發 replay,否則 replay 可能
        // 在 park commit 之前執行、無事可 replay,使下方第二個訂閱永遠等不到 redelivery。
        // 輪詢真實前提條件(而非固定 sleep);上限作為快速失敗的兜底,非時序假設。
        // 必須用 `#require`(拋錯中止)而非 `#expect`(只記錄、會繼續執行)——
        // 否則 park 未觀察到時仍會往下 replay 並卡在下方 subscription2.events 無限等待。
        var parkedReady = false
        for _ in 0 ..< 50 {
            if try await ps.getInfo().parkedMessageCount >= 1 { parkedReady = true; break }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        try #require(parkedReady, "park 未在預期時間內 commit;replay 無事可做")

        // Trigger replay — parked messages are re-queued for delivery
        try await ps.replayParked()

        let subscription2 = try await ps.subscribe()
        // Verify the event is re-delivered and ACK it
        var redelivered = false
        for try await result in subscription2.events {
            try await subscription2.ack(readEvents: result.event)
            redelivered = true
            break
        }

        #expect(redelivered)
        try await ps.delete()
        try await client.streams(specified: streamName).delete()
    }
}
