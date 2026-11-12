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
import NIOPosix
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

    /// Waits until the condition holds or the time runs out. Only for waiting on asynchronous teardown (when a task ends after a cancel depends on scheduling).
    private func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    // MARK: - Shared connections

    /// The central claim of the change. Discovery's gossip probes use shared connections too, so the count after the
    /// first call may be more than 1 (it depends on the seeds probed); what is checked is that it does not grow afterwards.
    @Test("After warming up, 200 more appends create no further shared connection")
    func appendsReuseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
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

    @Test("Concurrent appends share one connection")
    func concurrentAppendsReuseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
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
    @Test("Successful and failed reads both use the shared connection and do not affect later appends")
    func finiteReadsUseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event(), event()]) { $0.expectedRevision = .any }
        let warmed = client.selector.connections.createdSharedConnectionCount

        var count = 0
        for try await _ in try await stream.read().buffered {
            count += 1
        }
        #expect(count == 2)

        let missing = client.streams(specified: "ConnectionReuse-missing-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            for try await _ in try await missing.read().buffered {}
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

    @Test("readAll, projection statistics and user details all use the shared connection")
    func otherBufferedUsecasesUseSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        let warmed = client.selector.connections.createdSharedConnectionCount

        for _ in 0 ..< 20 {
            for try await _ in try await client.allStreams.read(configure: { $0.limit = 5 }).buffered {}
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
    @Test("150 concurrent reads all complete, so do appends meanwhile, and the shared connection serving them is not replaced")
    func manyConcurrentReadsDoNotStarveAppends() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: (0 ..< 20).map { _ in event() }) { $0.expectedRevision = .any }
        let endpoint = try #require(await client.selector.selectedNode?.endpoint)
        let generation = try #require(client.selector.connections.sharedEntrySnapshot(for: endpoint)?.generation)

        let readCounts = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0 ..< 150 {
                group.addTask {
                    var n = 0
                    for try await _ in try await stream.read().buffered { n += 1 }
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
    @Test("Cancelling a read being drained returns its lease, and the shared connection stays usable")
    func cancellingReadMidDrainReleasesLease() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        for _ in 0 ..< 2 {
            _ = try await stream.append(events: (0 ..< 5000).map { _ in event() }) { $0.expectedRevision = .any }
        }
        let warmed = client.selector.connections.createdSharedConnectionCount
        let endpoint = try #require(await client.selector.selectedNode?.endpoint)
        let baseline = try #require(client.selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount)

        let reader = Task {
            for try await _ in try await stream.read().buffered {}
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

    @Test("A read during shutdown ends in bounded time and does not hang")
    func shutdownDuringReadEndsIteration() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: (0 ..< 2000).map { _ in event() }) { $0.expectedRevision = .any }

        let reader = Task {
            do {
                for try await _ in try await stream.read().buffered {}
            } catch {}
        }
        try await Task.sleep(for: .milliseconds(5))
        client.shutdown()

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

    @Test("Cancelling one subscription does not affect the client's other subscriptions and unary calls")
    func cancellingOneSubscriptionLeavesOthersWorking() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
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

    /// A helper creates the client locally and returns only the subscription: it must keep working after the client and the facade are released.
    @Test("A subscription returned by a helper keeps working after the client and the facade are released")
    func returnedSubscriptionOutlivesClient() async throws {
        let streamName = "ConnectionReuse-\(UUID().uuidString)"

        func makeSubscription() async throws -> Streams<SpecifiedStream>.Subscription {
            let local = KurrentDBClient(settings: settings)
            return try await local.streams(specified: streamName).subscribe()
        }
        let subscription = try await makeSubscription()

        let writer = KurrentDBClient(settings: settings)
        defer { writer.shutdown() }
        let appended = try await writer.streams(specified: streamName)
            .append(events: [event()]) { $0.expectedRevision = .any }

        let received = try await subscription.events.first { _ in true }
        #expect(received?.record.revision == appended.currentRevision)

        subscription.cancel()
        try await writer.streams(specified: streamName).delete()
    }

    /// Every subscription has its own connection, so the server's limit on concurrent streams per connection does not queue them behind each other.
    @Test("150 concurrent subscriptions are all confirmed")
    func manyConcurrentSubscriptionsAreConfirmed() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { client.shutdown() }
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

        // With all 150 subscriptions open, a unary call still completes.
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }

        subscriptions.forEach { $0.cancel() }
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
        try await stream.delete()
    }

    // MARK: - Injected event-loop group

    /// The client runs every kind of call on a group it is given and never shuts that group down:
    /// shutting it down afterwards is the caller's job and completes. This alone does not show the
    /// calls ran on the group (NIO closes channels still registered when a group shuts down); the
    /// next test does.
    @Test("A client on a private one-thread group appends, reads lazily and subscribes; shutting the group down after client.shutdown() completes", .timeLimit(.minutes(1)))
    func privateOneThreadGroupCarriesEveryCall() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = KurrentDBClient(settings: settings, eventLoopGroup: group)
        #expect(client.selector.connections.eventLoopGroup === group)
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")

        _ = try await stream.append(events: (0 ..< 3).map { _ in event() }) { $0.expectedRevision = .any }
        var read = 0
        for try await response in stream.read() {
            if case .event = response { read += 1 }
        }
        #expect(read == 3)

        let subscription = try await stream.subscribe()
        let appended = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        let received = try await subscription.events.first { _ in true }
        #expect(received?.record.revision == appended.currentRevision)
        subscription.cancel()

        try await stream.delete()
        client.shutdown()

        // shutdownGracefully() ignores cancellation, so the time limit above, not a racing timer,
        // is what turns a hang into a failure.
        try await group.shutdownGracefully()
    }

    /// What makes the test above non-vacuous: had the transports run on NIO's singleton, the
    /// private group would be idle and its shutdown would complete whatever the client did. With
    /// the group's only thread blocked, a call that runs on it waits; one on the singleton would not.
    @Test("The client's calls run on the injected group: blocking its only thread delays the next append")
    func injectedGroupCarriesTheConnections() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let client = KurrentDBClient(settings: settings, eventLoopGroup: group)
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }

        group.next().execute { Thread.sleep(forTimeInterval: 1) }
        let started = ContinuousClock.now
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }
        #expect(ContinuousClock.now - started >= .milliseconds(800))

        try await stream.delete()
        client.shutdown()
        try await group.shutdownGracefully()
    }

    // MARK: - Shutdown

    @Test("shutdown ends subscriptions in progress and refuses every later call (the node still cached)")
    func shutdownEndsSubscriptionsAndRejectsCalls() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "ConnectionReuse-\(UUID().uuidString)")
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }   // the node enters the cache
        let subscription = try await stream.subscribe()

        let consumer = Task {
            do {
                for try await _ in subscription.events {}
            } catch {}
        }

        client.shutdown()

        // The subscription must end in bounded time, not hang forever.
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
            for try await _ in try await stream.read().buffered {}
        }
        #expect(client.selector.connections.activeDedicatedConnectionCount == 0)
    }
}
