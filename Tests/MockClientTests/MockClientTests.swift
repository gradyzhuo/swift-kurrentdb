//
//  MockClientTests.swift
//  swift-kurrentdb
//

import Foundation
@testable import KurrentDB
import Testing

// MARK: - Example Domain Services
//
// These lightweight service types accept `any KurrentDBClientProtocol`, making them
// fully testable without a live KurrentDB server. The MockClient tests verify that each
// service routes to the correct factory — the right stream name, group, or target type.

/// Routes domain events to per-customer order streams.
struct OrderEventService {
    let db: any KurrentDBClientProtocol

    func ordersStream(for customerId: String) -> Streams<SpecifiedStream> {
        db.streams(specified: "orders-\(customerId)")
    }

    func allEventsStream() -> Streams<AllStreamsTarget> {
        db.allStreams
    }
}

/// Manages persistent subscription lifecycle for a given subscription group.
struct SubscriptionManager {
    let db: any KurrentDBClientProtocol

    /// Subscribe to a specific stream with a named consumer group.
    func orderSubscription(stream: String, group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget> {
        db.persistentSubscriptions(stream: stream, group: group)
    }

    /// Subscribe to all streams, filtered by consumer group name.
    func allStreamsSubscription(group: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget> {
        db.persistentSubscriptions(filterGroup: group)
    }

    /// List subscriptions for a specific stream.
    func subscriptions(forStream stream: String) -> PersistentSubscriptions<FilterStreamPersistentSubscriptionTarget> {
        db.persistentSubscriptions(filterStream: stream)
    }

    /// Access cluster-wide subscription operations.
    var clusterSubscriptions: PersistentSubscriptions<AllPersistentSubscriptionTarget> {
        db.allPersistentSubscriptions
    }
}

/// Wraps user management operations.
struct UserAdminService {
    let db: any KurrentDBClientProtocol

    func allUsers() -> Users<AllUsersTarget> {
        db.users
    }

    func user(loginName: String) -> Users<SpecifiedUserTarget> {
        db.user(loginName)
    }
}

/// Wraps server operations.
struct ServerAdminService {
    let db: any KurrentDBClientProtocol

    func scavengeOps() -> Operations<ScavengeOperations> {
        db.operations(of: .scavenge)
    }

    func activeScavenge(id: String) -> Operations<ActiveScavenge> {
        db.operations(of: .activeScavenge(scavengeId: id))
    }

    func systemOps() -> Operations<SystemOperations> {
        db.operations(of: .system)
    }

    func nodeOps() -> Operations<NodeOperations> {
        db.operations(of: .node)
    }

    var clusterMonitoring: Monitoring {
        db.monitoring
    }
}

// MARK: - Tests

@Suite("MockKurrentDBClient Unit Tests", .serialized)
struct MockClientTests {

    // MARK: - Conformance

    @Test("MockKurrentDBClient conforms to KurrentDBClientProtocol")
    func testConformance() {
        let mock = MockKurrentDBClient()
        // Compile-time verification that MockKurrentDBClient satisfies the protocol.
        let _: any KurrentDBClientProtocol = mock
        // If this test compiles, the conformance is correct.
    }

    // MARK: - Streams Factory Recording

    @Test("streams(specified:) records the stream name")
    func testStreamsSpecifiedRecordsName() {
        let mock = MockKurrentDBClient()
        _ = mock.streams(specified: "my-stream")
        #expect(mock.streamsCalls == [.specified("my-stream")])
    }

    @Test("allStreams records .all")
    func testAllStreamsRecordsAll() {
        let mock = MockKurrentDBClient()
        _ = mock.allStreams
        #expect(mock.streamsCalls == [.all])
    }

    @Test("multiStreams records .multiple")
    func testMultiStreamsRecordsMultiple() {
        let mock = MockKurrentDBClient()
        _ = mock.multiStreams
        #expect(mock.streamsCalls == [.multiple])
    }

    @Test("Multiple streams(specified:) calls are all recorded in order")
    func testMultipleStreamsCallsRecordedInOrder() {
        let mock = MockKurrentDBClient()
        _ = mock.streams(specified: "first")
        _ = mock.streams(specified: "second")
        _ = mock.streams(specified: "third")
        #expect(mock.streamsCalls == [.specified("first"), .specified("second"), .specified("third")])
    }

    // MARK: - Persistent Subscriptions Factory Recording

    @Test("persistentSubscriptions(stream:group:) records stream and group")
    func testPSStreamGroupRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.persistentSubscriptions(stream: "orders", group: "consumer-group-1")
        #expect(mock.persistentSubscriptionsCalls == [.streamGroup(stream: "orders", group: "consumer-group-1")])
    }

    @Test("persistentSubscriptions(filterGroup:) records the group name")
    func testPSFilterGroupRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.persistentSubscriptions(filterGroup: "my-group")
        #expect(mock.persistentSubscriptionsCalls == [.filterGroup("my-group")])
    }

    @Test("persistentSubscriptions(filterStream:) records the stream name")
    func testPSFilterStreamRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.persistentSubscriptions(filterStream: "orders")
        #expect(mock.persistentSubscriptionsCalls == [.filterStream("orders")])
    }

    @Test("allPersistentSubscriptions records .all")
    func testAllPSRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.allPersistentSubscriptions
        #expect(mock.persistentSubscriptionsCalls == [.all])
    }

    // MARK: - Users Factory Recording

    @Test("users property records .all")
    func testUsersAllRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.users
        #expect(mock.usersCalls == [.all])
    }

    @Test("user(_:) records the login name")
    func testUserSpecifiedRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.user("alice")
        #expect(mock.usersCalls == [.specified("alice")])
    }

    // MARK: - Operations Factory Recording

    @Test("operations(of: .scavenge) records .scavenge")
    func testOperationsScavengeRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.operations(of: .scavenge)
        #expect(mock.operationsCalls == [.scavenge])
    }

    @Test("operations(of: .activeScavenge(scavengeId:)) records the ID")
    func testOperationsActiveScavengeRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.operations(of: .activeScavenge(scavengeId: "scavenge-abc"))
        #expect(mock.operationsCalls == [.activeScavenge("scavenge-abc")])
    }

    @Test("operations(of: .system) records .system")
    func testOperationsSystemRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.operations(of: .system)
        #expect(mock.operationsCalls == [.system])
    }

    @Test("operations(of: .node) records .node")
    func testOperationsNodeRecorded() {
        let mock = MockKurrentDBClient()
        _ = mock.operations(of: .node)
        #expect(mock.operationsCalls == [.node])
    }

    // MARK: - Monitoring

    @Test("monitoring access is counted")
    func testMonitoringAccessCounted() {
        let mock = MockKurrentDBClient()
        _ = mock.monitoring
        _ = mock.monitoring
        #expect(mock.monitoringAccessCount == 2)
    }

    // MARK: - Domain Service Integration Tests

    @Test("OrderEventService routes to per-customer stream name")
    func testOrderEventServiceRoutesCorrectly() {
        let mock = MockKurrentDBClient()
        let service = OrderEventService(db: mock)

        _ = service.ordersStream(for: "cust-123")

        #expect(mock.streamsCalls.last == .specified("orders-cust-123"))
    }

    @Test("OrderEventService uses allStreams for global read")
    func testOrderEventServiceUsesAllStreams() {
        let mock = MockKurrentDBClient()
        let service = OrderEventService(db: mock)

        _ = service.allEventsStream()

        #expect(mock.streamsCalls.last == .all)
    }

    @Test("SubscriptionManager routes stream+group subscription correctly")
    func testSubscriptionManagerStreamGroupRouting() {
        let mock = MockKurrentDBClient()
        let manager = SubscriptionManager(db: mock)

        _ = manager.orderSubscription(stream: "orders", group: "payment-processor")

        #expect(mock.persistentSubscriptionsCalls.last == .streamGroup(stream: "orders", group: "payment-processor"))
    }

    @Test("SubscriptionManager routes all-streams group subscription correctly")
    func testSubscriptionManagerAllStreamsGroupRouting() {
        let mock = MockKurrentDBClient()
        let manager = SubscriptionManager(db: mock)

        _ = manager.allStreamsSubscription(group: "audit-log")

        #expect(mock.persistentSubscriptionsCalls.last == .filterGroup("audit-log"))
    }

    @Test("SubscriptionManager routes filterStream subscription correctly")
    func testSubscriptionManagerFilterStreamRouting() {
        let mock = MockKurrentDBClient()
        let manager = SubscriptionManager(db: mock)

        _ = manager.subscriptions(forStream: "payments")

        #expect(mock.persistentSubscriptionsCalls.last == .filterStream("payments"))
    }

    @Test("UserAdminService accesses allUsers correctly")
    func testUserAdminServiceAllUsers() {
        let mock = MockKurrentDBClient()
        let service = UserAdminService(db: mock)

        _ = service.allUsers()

        #expect(mock.usersCalls.last == .all)
    }

    @Test("UserAdminService routes to specific user by login name")
    func testUserAdminServiceSpecificUser() {
        let mock = MockKurrentDBClient()
        let service = UserAdminService(db: mock)

        _ = service.user(loginName: "bob@example.com")

        #expect(mock.usersCalls.last == .specified("bob@example.com"))
    }

    @Test("ServerAdminService selects scavenge operations target")
    func testServerAdminServiceScavenge() {
        let mock = MockKurrentDBClient()
        let service = ServerAdminService(db: mock)

        _ = service.scavengeOps()

        #expect(mock.operationsCalls.last == .scavenge)
    }

    @Test("ServerAdminService selects system operations target")
    func testServerAdminServiceSystem() {
        let mock = MockKurrentDBClient()
        let service = ServerAdminService(db: mock)

        _ = service.systemOps()

        #expect(mock.operationsCalls.last == .system)
    }

    @Test("ServerAdminService tracks monitoring access")
    func testServerAdminServiceMonitoring() {
        let mock = MockKurrentDBClient()
        let service = ServerAdminService(db: mock)

        _ = service.clusterMonitoring

        #expect(mock.monitoringAccessCount == 1)
    }

    // MARK: - Independence Verification

    @Test("Different factory types are tracked independently")
    func testCallLogsAreIndependent() {
        let mock = MockKurrentDBClient()

        _ = mock.streams(specified: "orders")
        _ = mock.users
        _ = mock.operations(of: .system)
        _ = mock.monitoring

        #expect(mock.streamsCalls.count == 1)
        #expect(mock.usersCalls.count == 1)
        #expect(mock.operationsCalls.count == 1)
        #expect(mock.monitoringAccessCount == 1)
        #expect(mock.persistentSubscriptionsCalls.count == 0)
    }
}
