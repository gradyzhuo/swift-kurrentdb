# ReadCall `.lazy` / `.buffered` & Subscription Backpressure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Streams<Target>.ReadCall` — returned by a new synchronous `read(configure:)` overload — whose `.lazy` iterates events with backpressure and closes the RPC when the iterator is released, and whose `.buffered` is today's whole-result read; replace the unbounded buffers in `Subscribe`/`SubscribeAll` with the same bounded hand-off. No existing public API changes meaning, type, or gets deprecated.

**Architecture:** A package-level single-producer/single-consumer `ResponseHandoff<Element>` (fixed capacity, `Mutex` + `CheckedContinuation`) carries messages from the gRPC response handler to the consumer, so HTTP/2 flow control pushes back on the server. `open(node:)` starts a read RPC on the shared connection lease inside a `Task`, waits until the server accepts the call, and returns a `ScopedCall` (hand-off + lease + task). `ReadCall.Lazy.Iterator` is a class that opens the call on its first `next()` and closes it when it finishes, throws, or is deinitialised. `ReadCall.buffered` and the existing `read()` share the existing `BufferedStreamResponse` path untouched.

**Tech Stack:** Swift 6.0+, grpc-swift 2 (`GRPCCore`, `GRPCNIOTransportHTTP2Posix`), `Synchronization.Mutex`, SwiftNIO (`NIOPosix`, transitively available), Swift Testing. Live tests need the 3-node TLS cluster (`server/docker-compose.yaml`, ports 2111–2113; `docker compose -f server/docker-compose.yaml up -d`).

**Spec:** `docs/superpowers/specs/2026-10-06-read-call-lazy-buffered-design.md` (binding). 3.0 decision: `docs/adr/0001-read-becomes-lazy-in-3-0.md`.

## Global Constraints

- Swift 6.0 or later; platforms as in `Package.swift` (macOS 15+). New code must compile on Swift 6.0 (Task 7 builds it in Docker `swift:6.0-jammy`).
- No new package dependencies. `import NIOCore` / `import NIOPosix` in tests resolve transitively (existing convention: `KurrentDB` already `import NIO` without declaring it).
- No public API breaks and **no deprecation**: `read(configure:) async throws(KurrentError) -> AsyncThrowingStream<…>`, `subscribe`, `Subscription.events` / `subscriptionId` / `cancel()`, `KurrentDBClientProtocol` keep their exact signatures and behaviour.
- The new `read(configure:) -> ReadCall` overloads are **synchronous and non-throwing**, and `ReadCall` does **not** conform to `AsyncSequence` (spec §6; otherwise existing call sites become ambiguous).
- Public names: `Streams<Target>.ReadCall`, `ReadCall.lazy: ReadCall.Lazy`, `ReadCall.buffered` (`get async throws(KurrentError)`), `ReadCall.Lazy.Iterator`. Element type `ReadResponse`.
- `ResponseHandoff` default capacity 1.
- All `//` and `///` comments in English.
- Commit messages: `[TAG] short description in English` (`[ADD]`, `[UPDATE]`, `[FIX]`, `[REFACTOR]`). **No `Co-Authored-By:` lines.** `git add` explicit paths only (the checkout has many unrelated untracked files).
- Implementers work from this plan and the spec only; the branch `feat/scoped-read-delivery` is NOT a source — reviewers may consult it as an edge-case checklist.

## Review Focus

1. `.lazy` iterator created (`makeAsyncIterator()`) but never advanced, then dropped → no RPC, no lease taken, nothing to clean up. (Task 4: `droppedIteratorTakesNoLease`)
2. The same `Lazy` value iterated twice → two independent RPCs, both closed, both leases returned; the first iteration's `break` does not affect the second. (Task 5: `lazyIsReiterable`)
3. Consumer `break`s after the first element → `retainCount` returns to 0 (asynchronously), production stays bounded (`sentCount - deliveredCount <= capacity`, `sentCount < total`). (Task 5: `earlyBreakReleasesLease`)
4. Error after acceptance (missing stream) on `.lazy` → thrown during iteration, identical description to `read()`, then `next()` returns nil and the lease is returned. (Task 5: `missingStreamMatchesBuffered`)
5. `Subscription.cancel()` while the consumer is suspended → loop ends normally, dedicated connection closes. (Task 6: `cancelWhileWaiting`)

---

## File Structure

| File | Responsibility |
|---|---|
| Create `Sources/KurrentDB/Core/ResponseHandoff.swift` | Bounded SPSC hand-off; `makeStream` with cancel-on-release sentinel |
| Modify `Sources/GRPCEncapsulates/ResponseHandlable.swift` | Add `ScopedStreamResponse` protocol |
| Create `Sources/KurrentDB/Core/Additions/Usecase/UnaryStream+Scoped.swift` | `AcceptanceGate`, `ScopedCall`, `open(node:callOptions:credentials:)` |
| Modify `Sources/KurrentDB/Streams/Usecase/Specified/Streams.Read.swift`, `…/All/Streams.ReadAll.swift` | Conform to `ScopedStreamResponse` |
| Create `Sources/KurrentDB/Streams/Streams.ReadCall.swift` | `ReadCall`, `Lazy`, `Lazy.Iterator`, `buffered` |
| Modify `Sources/KurrentDB/Streams/API/Streams+SpecifiedStreamTarget.swift`, `…/Streams+AllStreamsTarget.swift` | New `read(configure:) -> ReadCall` overloads; doc line on the existing `read` |
| Modify `Sources/KurrentDB/Streams/Streams.Subscription.swift`, `…/Specified/Streams.Subscribe.swift`, `…/All/Streams.SubscribeAll.swift` | Hand-off based subscriptions |
| Create `Tests/MockClientTests/ResponseHandoffTests.swift` | Offline hand-off tests |
| Create `Tests/MockClientTests/LazyReadPathTests.swift` | Offline lazy-read path tests (refused port, silent listener) |
| Create `Tests/MockClientTests/ReadOverloadResolutionTests.swift` | Compile-level overload checks |
| Create `Tests/StreamsTests/LazyReadLiveTests.swift` | Live: spike, lazy behaviour |
| Create `Tests/StreamsTests/SubscriptionBackpressureLiveTests.swift` | Live: subscription backpressure |
| Modify `Sources/KurrentDB/KurrentDB.docc/Articles/Reading events.md`, `README.md` | Docs |

Existing helpers you will use (all on `main`): `ConnectionProvider.acquire(_:) throws(KurrentError) -> SharedLease` (`SharedLease.client`, `.release()` idempotent); `ConnectionProvider.createdSharedConnectionCount`, `createdDedicatedConnectionCount`, `activeDedicatedConnectionCount`, `sharedEntrySnapshot(for:)?.retainCount`, `shutdown()`; `NodeSelector.select() async throws(KurrentError) -> Node`, `retryPolicy`, `invalidate()`, `connections`, `cacheNodeForTesting(_:)`; `Node(endpoint:settings:serverInfo:connections:)`, `node.serverInfo.isSupported(method:)`; `withRetry(policy:selectNode:invalidate:operation:) async throws(KurrentError)` (`Core/RetryPolicy.swift`); `withRethrowingError(usage:action:)` (`Core/Error/KurrentError.swift`); `Metadata(from:overriding:) throws(KurrentError)`; `UnaryRequestBuildable.request(metadata:)`; `ServerFeatures.ServiceInfo(serverVersion:supportedMethods:)`, `ServerFeatures.SupportedMethod(methodName:serviceName:features:)`.

---

### Task 1: Live spike — cancelling one RPC leaves the shared connection intact

Gate for the whole `.lazy` design. If it fails, stop and report: `.lazy` must then use `node.connections.openDedicated(for:)` instead of `acquire(_:)`.

**Files:**
- Create: `Tests/StreamsTests/LazyReadLiveTests.swift`

**Interfaces:**
- Produces: suite `LazyReadLiveTests` with helpers `settings`, `event(_:)`, `eventually(timeout:_:)`, `appendEvents(count:to:)`, `sharedRetainCount(_:)` reused by Task 5.

- [ ] **Step 1: Write the test**

```swift
//
//  LazyReadLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml.
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Testing

@Suite("Lazy read (live)", .serialized, .timeLimit(.minutes(3)))
struct LazyReadLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    func event(_ type: String = "LazyRead-Test") -> EventData {
        EventData(eventType: type, model: ["Description": "lazy read"])
    }

    /// Waits until the condition holds or the timeout passes. Lease release after a lazy read
    /// happens in the iterator's deinit, asynchronously, so tests poll for it.
    func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    func appendEvents(count: Int, to stream: Streams<SpecifiedStream>) async throws {
        _ = try await stream.append(events: (0 ..< count).map { _ in event() }) { $0.expectedRevision = .any }
    }

    /// Retain count of the shared connection the client is currently routed to.
    func sharedRetainCount(_ client: KurrentDBClient) async throws -> Int? {
        let node = try await client.selector.select()
        return client.selector.connections.sharedEntrySnapshot(for: node.endpoint)?.retainCount
    }

    @Test("Cancelling one in-flight server-streaming RPC does not disturb another on the same shared connection")
    func cancellingOneRPCKeepsSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "LazyRead-Spike-\(UUID().uuidString)"
        let stream = client.streams(specified: name)
        try await appendEvents(count: 200, to: stream)

        let node = try await client.selector.select()
        let createdBefore = client.selector.connections.createdSharedConnectionCount
        let lease = try node.connections.acquire(node.endpoint)
        defer { lease.release() }

        // RPC A: a live subscription from the start — the server can never finish it.
        var subscribeOptions = Streams<SpecifiedStream>.Subscribe.Options()
        subscribeOptions.revision = .start
        let request = ClientRequest(
            message: try Streams<SpecifiedStream>.Subscribe(from: .init(name: name), options: subscribeOptions).requestMessage(),
            metadata: try Metadata(from: node.settings)
        )
        let (firstEvent, firstEventSignal) = AsyncStream.makeStream(of: Void.self)
        let parked = Task {
            defer { firstEventSignal.finish() }
            let service = Streams<SpecifiedStream>.UnderlyingClient(wrapping: lease.client)
            try await service.read(request: request) { response in
                for try await message in response.messages {
                    if case .event = message.content {
                        firstEventSignal.yield()
                        break
                    }
                }
                try await Task.sleep(for: .seconds(60))   // park until cancelled
            }
        }

        // Wait until A is provably in flight (bounded).
        let arrived = await withTaskGroup(of: Bool.self) { group in
            group.addTask { for await _ in firstEvent { return true }; return false }
            group.addTask { try? await Task.sleep(for: .seconds(10)); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
        try #require(arrived, "RPC A never received its first event")

        // RPC B on the same shared connection, while A is parked and again after A is cancelled.
        let before = try await stream.read().reduce(0) { count, _ in count + 1 }
        parked.cancel()
        let outcome = await parked.result
        let after = try await stream.read().reduce(0) { count, _ in count + 1 }

        switch outcome {
        case .success:
            Issue.record("RPC A ended without being cancelled")
        case let .failure(error):
            let cancelled = error is CancellationError || (error as? RPCError)?.code == .cancelled
            #expect(cancelled, "RPC A ended with \(error) instead of cancellation")
        }
        #expect(before == 200)
        #expect(after == 200)
        #expect(client.selector.connections.createdSharedConnectionCount == createdBefore)
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --no-parallel --filter LazyReadLiveTests/cancellingOneRPCKeepsSharedConnection`
Expected: PASS. If `createdSharedConnectionCount` grew or `after != 200`, stop and report.

- [ ] **Step 3: Commit**

```bash
git add Tests/StreamsTests/LazyReadLiveTests.swift
git commit -m "[ADD] live spike: cancelling one RPC keeps the shared connection"
```

---

### Task 2: `ResponseHandoff`

**Files:**
- Create: `Sources/KurrentDB/Core/ResponseHandoff.swift`
- Test: `Tests/MockClientTests/ResponseHandoffTests.swift`

**Interfaces:**
- Produces: `package final class ResponseHandoff<Element: Sendable>: Sendable` with
  - `init(capacity: Int = 1, onTermination: @escaping @Sendable ((any Error)?) -> Void = { _ in })` — `capacity >= 1`
  - `func send(_ element: Element) async throws` — suspends while full; throws `CancellationError` once the hand-off ended; cancellation of the *producer's* task inside `send` behaves like `finish(throwing: CancellationError())`
  - `func next() async throws -> Element?` — single consumer (precondition); consumer-task cancellation → `cancel()` (quiet `nil`)
  - `func finish(throwing error: (any Error)? = nil)` — producer side; wakes a pending producer with `CancellationError`; idempotent
  - `func cancel()` — consumer side; drops the buffer (also after `finish`); idempotent
  - `func makeStream() -> AsyncThrowingStream<Element, any Error>`, `func makeStream<T: Sendable>(_ transform: @escaping @Sendable (Element) throws -> T?) -> AsyncThrowingStream<T, any Error>` (nil skips; any thrown error cancels the hand-off)
  - `var sentCount: Int`, `var deliveredCount: Int`, `let capacity: Int`
  - `onTermination` fires exactly once: `finish` → its error; `cancel` (before finish) → `nil`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  ResponseHandoffTests.swift
//  swift-kurrentdb
//

import Synchronization
import Testing
@testable import KurrentDB

private struct Boom: Error, Equatable {}

/// Records onTermination calls.
private final class TerminationProbe: Sendable {
    private let calls = Mutex<[String]>([])
    var count: Int { calls.withLock { $0.count } }
    var last: String? { calls.withLock { $0.last } }
    func record(_ error: (any Error)?) { calls.withLock { $0.append(error.map { "\($0)" } ?? "nil") } }
}

@Suite("ResponseHandoff", .timeLimit(.minutes(1)))
struct ResponseHandoffTests {
    /// Polls until the condition holds (bounded); used for positive waits so the test does not
    /// depend on scheduler timing.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0 ..< 2000 where !condition() { await Task.yield() }
    }

    /// Gives spawned tasks a chance to make progress; used only for negative assertions.
    private func settle() async { for _ in 0 ..< 200 { await Task.yield() } }

    @Test("Delivers in order and ends with nil after finish")
    func deliversInOrder() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 2)
        let producer = Task { for i in 1 ... 5 { try await handoff.send(i) }; handoff.finish() }
        var received: [Int] = []
        while let value = try await handoff.next() { received.append(value) }
        try await producer.value
        #expect(received == [1, 2, 3, 4, 5])
        #expect(handoff.sentCount == 5)
        #expect(handoff.deliveredCount == 5)
    }

    @Test("finish(throwing:) surfaces the error after the buffer drains, then nil")
    func finishWithError() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 2)
        try await handoff.send(1)
        handoff.finish(throwing: Boom())
        #expect(try await handoff.next() == 1)
        await #expect(throws: Boom.self) { _ = try await handoff.next() }
        #expect(try await handoff.next() == nil)
    }

    @Test("The producer can run at most `capacity` elements ahead")
    func producerSuspendsWhenFull() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 1)
        let producer = Task { for i in 1 ... 10 { try await handoff.send(i) }; handoff.finish() }
        await waitUntil { handoff.sentCount == 1 }
        await settle()
        #expect(handoff.sentCount == 1)
        #expect(try await handoff.next() == 1)
        await waitUntil { handoff.sentCount == 2 }
        await settle()
        #expect(handoff.sentCount == 2)
        #expect(handoff.sentCount - handoff.deliveredCount <= 1)
        handoff.cancel()
        _ = await producer.result
    }

    @Test("cancel() wakes a suspended producer with CancellationError and fires onTermination once")
    func cancelWakesProducer() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        try await handoff.send(1)
        let producer = Task { try await handoff.send(2) }
        await settle()
        handoff.cancel()
        handoff.cancel()
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(try await handoff.next() == nil)
        #expect(probe.count == 1)
        #expect(probe.last == "nil")
    }

    @Test("finish fires onTermination with its error; a later cancel does not fire again")
    func finishThenCancelFiresOnce() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(onTermination: { probe.record($0) })
        handoff.finish(throwing: Boom())
        handoff.cancel()
        #expect(probe.count == 1)
        #expect(probe.last == "\(Boom())")
    }

    @Test("cancel() after finish() discards buffered elements so an escaped stream ends at once")
    func cancelAfterFinishDiscardsBuffer() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 2, onTermination: { probe.record($0) })
        let escaped = handoff.makeStream()
        try await handoff.send(42)
        handoff.finish()
        handoff.cancel()
        var iterator = escaped.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
        #expect(probe.count == 1)
    }

    @Test("cancel() after finish(throwing:) discards the pending error too")
    func cancelAfterFinishDiscardsError() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 2)
        try await handoff.send(1)
        handoff.finish(throwing: Boom())
        handoff.cancel()
        #expect(try await handoff.next() == nil)
    }

    @Test("Dropping an un-iterated stream cancels the hand-off")
    func droppedStreamCancels() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(onTermination: { probe.record($0) })
        do { _ = handoff.makeStream() }
        #expect(probe.count == 1)
        await #expect(throws: CancellationError.self) { try await handoff.send(1) }
    }

    @Test("Breaking out of the loop cancels the hand-off once the stream goes out of scope")
    func breakCancels() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        let producer = Task { for i in 1 ... 100 { try await handoff.send(i) }; handoff.finish() }
        func consumeFirst() async throws -> Int? {
            for try await value in handoff.makeStream() { return value }
            return nil
        }
        #expect(try await consumeFirst() == 1)
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(probe.count == 1)
    }

    @Test("Cancelling the consumer task cancels the hand-off and the consumer ends cleanly")
    func consumerTaskCancellation() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        let consumer = Task {
            var count = 0
            for try await _ in handoff.makeStream() { count += 1 }
            return count
        }
        await settle()
        consumer.cancel()
        let outcome = await consumer.result
        #expect(try outcome.get() == 0)
        #expect(probe.count == 1)
        await #expect(throws: CancellationError.self) { try await handoff.send(1) }
    }

    @Test("Cancelling the producer's task is not a clean end for the consumer")
    func producerCancellationIsNotACleanEnd() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 1, onTermination: { probe.record($0) })
        try await handoff.send(1)
        let producer = Task { try await handoff.send(2) }
        await settle()
        producer.cancel()
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(try await handoff.next() == 1)
        await #expect(throws: CancellationError.self) { _ = try await handoff.next() }
        #expect(try await handoff.next() == nil)
        #expect(probe.count == 1)
        #expect(probe.last == "\(CancellationError())")
    }

    @Test("finish() wakes a suspended producer with CancellationError")
    func finishReleasesPendingProducer() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 1)
        try await handoff.send(1)
        let producer = Task { try await handoff.send(2) }
        await settle()
        handoff.finish()
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(handoff.sentCount == 1)
        #expect(try await handoff.next() == 1)
        #expect(try await handoff.next() == nil)
    }

    @Test("A consumer suspended in next() receives the error from finish(throwing:), then nil")
    func waitingConsumerReceivesFinishError() async throws {
        let handoff = ResponseHandoff<Int>()
        let consumer = Task { try await handoff.next() }
        await settle()
        handoff.finish(throwing: Boom())
        await #expect(throws: Boom.self) { _ = try await consumer.value }
        #expect(try await handoff.next() == nil)
    }

    @Test("makeStream(_:) skips elements the transform maps to nil")
    func transformSkips() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 4)
        for i in 1 ... 4 { try await handoff.send(i) }
        handoff.finish()
        var received: [Int] = []
        for try await value in handoff.makeStream({ $0 % 2 == 0 ? $0 : nil }) { received.append(value) }
        #expect(received == [2, 4])
    }

    @Test("A throwing stream transform ends the hand-off")
    func throwingTransformEndsHandoff() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(capacity: 2, onTermination: { probe.record($0) })
        try await handoff.send(1)
        let stream: AsyncThrowingStream<Int, any Error> = handoff.makeStream { _ in throw Boom() }
        var iterator = stream.makeAsyncIterator()
        await #expect(throws: Boom.self) { _ = try await iterator.next() }
        #expect(probe.count == 1)
        await #expect(throws: CancellationError.self) { try await handoff.send(2) }
        #expect(try await iterator.next() == nil)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter ResponseHandoffTests`
Expected: FAIL to compile — `cannot find 'ResponseHandoff' in scope`.

- [ ] **Step 3: Implement**

```swift
//
//  ResponseHandoff.swift
//  KurrentCore
//

import Synchronization

/// Single-producer / single-consumer hand-off with a fixed capacity.
///
/// The producer (a gRPC response handler) suspends in ``send(_:)`` while `capacity` elements
/// are waiting, so it stops pulling from the transport; HTTP/2 flow control then stops the
/// server. ``finish(throwing:)`` is called by the producer, ``cancel()`` by the consumer side
/// (directly, on task cancellation, or when the stream from ``makeStream()`` is released).
/// `onTermination` runs exactly once, on whichever of the two happens first.
///
/// Cancellation is split by side. Consumer-side cancellation ends quietly: the buffer is dropped
/// and `next()` returns `nil`. Cancelling the producer's task inside ``send(_:)`` instead behaves
/// like `finish(throwing: CancellationError())`: the consumer drains the buffer and then receives
/// `CancellationError`, so truncated data never looks like a clean end. ``finish(throwing:)`` also
/// wakes a suspended producer with `CancellationError`.
package final class ResponseHandoff<Element: Sendable>: Sendable {
    private enum Terminal {
        case finished((any Error)?)
        case cancelled
    }

    private struct State {
        var buffer: [Element] = []
        var terminal: Terminal?
        var consumer: CheckedContinuation<Element?, any Error>?
        var producer: (element: Element, continuation: CheckedContinuation<Void, any Error>)?
        var sentCount = 0
        var deliveredCount = 0
    }

    private enum SendAction {
        case fail
        case resumeConsumer(CheckedContinuation<Element?, any Error>)
        case done
        case suspend
    }

    private enum NextAction {
        case deliver(Element, wake: CheckedContinuation<Void, any Error>?)
        case fail(any Error)
        case end
        case suspend
    }

    package let capacity: Int
    private let state = Mutex(State())
    private let onTermination: @Sendable ((any Error)?) -> Void

    package init(capacity: Int = 1, onTermination: @escaping @Sendable ((any Error)?) -> Void = { _ in }) {
        precondition(capacity >= 1, "ResponseHandoff capacity must be at least 1")
        self.capacity = capacity
        self.onTermination = onTermination
    }

    /// Number of elements accepted from the producer.
    package var sentCount: Int { state.withLock { $0.sentCount } }

    /// Number of elements handed to the consumer.
    package var deliveredCount: Int { state.withLock { $0.deliveredCount } }

    package func send(_ element: Element) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let action: SendAction = state.withLock { state in
                    if state.terminal != nil { return .fail }
                    if let consumer = state.consumer {
                        state.consumer = nil
                        state.sentCount += 1
                        state.deliveredCount += 1
                        return .resumeConsumer(consumer)
                    }
                    if state.buffer.count < capacity {
                        state.buffer.append(element)
                        state.sentCount += 1
                        return .done
                    }
                    state.producer = (element, continuation)
                    return .suspend
                }
                switch action {
                case .fail: continuation.resume(throwing: CancellationError())
                case let .resumeConsumer(consumer): consumer.resume(returning: element); continuation.resume()
                case .done: continuation.resume()
                case .suspend: break
                }
            }
        } onCancel: {
            // The producer's task was cancelled: that is an abnormal end, not a quiet one.
            finish(throwing: CancellationError())
        }
    }

    package func next() async throws -> Element? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Element?, any Error>) in
                let action: NextAction = state.withLock { state in
                    if !state.buffer.isEmpty {
                        let element = state.buffer.removeFirst()
                        state.deliveredCount += 1
                        var wake: CheckedContinuation<Void, any Error>?
                        if let pending = state.producer {
                            state.producer = nil
                            state.buffer.append(pending.element)
                            state.sentCount += 1
                            wake = pending.continuation
                        }
                        return .deliver(element, wake: wake)
                    }
                    switch state.terminal {
                    case let .finished(error?)?:
                        state.terminal = .finished(nil)   // an AsyncSequence ends after throwing once
                        return .fail(error)
                    case .finished(nil)?, .cancelled?:
                        return .end
                    case nil:
                        precondition(state.consumer == nil, "ResponseHandoff supports a single consumer")
                        state.consumer = continuation
                        return .suspend
                    }
                }
                switch action {
                case let .deliver(element, wake): wake?.resume(); continuation.resume(returning: element)
                case let .fail(error): continuation.resume(throwing: error)
                case .end: continuation.resume(returning: nil)
                case .suspend: break
                }
            }
        } onCancel: {
            cancel()
        }
    }

    package func finish(throwing error: (any Error)? = nil) {
        let (first, consumer, producer): (Bool, CheckedContinuation<Element?, any Error>?, CheckedContinuation<Void, any Error>?) = state.withLock { state in
            guard state.terminal == nil else { return (false, nil, nil) }
            let consumer = state.consumer
            let producer = state.producer?.continuation
            state.consumer = nil
            state.producer = nil
            // A waiting consumer means the buffer is empty: hand it the outcome directly and
            // leave the terminal error-free so the error is not delivered twice.
            state.terminal = (consumer != nil && error != nil) ? .finished(nil) : .finished(error)
            return (true, consumer, producer)
        }
        guard first else { return }
        if let consumer {
            if let error { consumer.resume(throwing: error) } else { consumer.resume(returning: nil) }
        }
        producer?.resume(throwing: CancellationError())
        onTermination(error)
    }

    package func cancel() {
        let (first, consumer, producer): (Bool, CheckedContinuation<Element?, any Error>?, CheckedContinuation<Void, any Error>?) = state.withLock { state in
            switch state.terminal {
            case .cancelled?:
                return (false, nil, nil)
            case .finished?:
                // The producer already ended and onTermination already fired, but the consumer
                // side still drops whatever it has not taken: a stream that escapes its scope
                // must end at once instead of delivering the tail or a pending error.
                state.terminal = .cancelled
                state.buffer.removeAll()
                return (false, nil, nil)
            case nil:
                state.terminal = .cancelled
                state.buffer.removeAll()
                let consumer = state.consumer
                let producer = state.producer?.continuation
                state.consumer = nil
                state.producer = nil
                return (true, consumer, producer)
            }
        }
        guard first else { return }
        consumer?.resume(returning: nil)
        producer?.resume(throwing: CancellationError())
        onTermination(nil)
    }

    /// Wraps the hand-off as a pull-based stream. Call at most once per hand-off.
    ///
    /// The stream's closure holds a sentinel that cancels the hand-off when the stream is
    /// released. An error thrown by `next()` or by `transform` also cancels it: an unfolding
    /// stream keeps its closure after throwing, so without this the hand-off would stay alive.
    package func makeStream<T: Sendable>(_ transform: @escaping @Sendable (Element) throws -> T?) -> AsyncThrowingStream<T, any Error> {
        let sentinel = CancelOnDeinit(self)
        return AsyncThrowingStream(unfolding: {
            do {
                while let element = try await sentinel.handoff.next() {
                    if let value = try transform(element) { return value }
                }
                return nil
            } catch {
                sentinel.handoff.cancel()
                throw error
            }
        })
    }

    package func makeStream() -> AsyncThrowingStream<Element, any Error> {
        makeStream { $0 }
    }
}

/// Cancels its hand-off when the stream that captured it is released.
private final class CancelOnDeinit<Element: Sendable>: Sendable {
    let handoff: ResponseHandoff<Element>
    init(_ handoff: ResponseHandoff<Element>) { self.handoff = handoff }
    deinit { handoff.cancel() }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `for i in 1 2 3 4 5; do swift test --no-parallel --filter ResponseHandoffTests || break; done`
Expected: 15 tests PASS on all 5 runs.

- [ ] **Step 5: Commit**

```bash
git add Sources/KurrentDB/Core/ResponseHandoff.swift Tests/MockClientTests/ResponseHandoffTests.swift
git commit -m "[ADD] ResponseHandoff: bounded single-producer hand-off with cancel-on-release stream"
```

---

### Task 3: `ScopedStreamResponse`, `AcceptanceGate`, `ScopedCall`, `open(node:)`

**Files:**
- Modify: `Sources/GRPCEncapsulates/ResponseHandlable.swift` (append)
- Create: `Sources/KurrentDB/Core/Additions/Usecase/UnaryStream+Scoped.swift`
- Modify: `Sources/KurrentDB/Streams/Usecase/Specified/Streams.Read.swift:12` (declaration) and body
- Modify: `Sources/KurrentDB/Streams/Usecase/All/Streams.ReadAll.swift:13` (declaration) and body
- Test: `Tests/MockClientTests/LazyReadPathTests.swift` (first half)

**Interfaces:**
- Consumes: `ResponseHandoff` (Task 2).
- Produces:
  - `package protocol ScopedStreamResponse: UnaryStream, BufferedStreamResponse` with `func call<Result: Sendable>(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, onResponse: @Sendable @escaping (StreamingClientResponse<UnderlyingResponse>) async throws -> Result) async throws -> Result`
  - `package final class ScopedCall<Response: Sendable>: Sendable` — `let handoff: ResponseHandoff<Response>`, `func close() async`, `func closeInBackground()`
  - `extension ScopedStreamResponse where Transport == HTTP2ClientTransport.Posix { package func open(node: Node, callOptions: CallOptions, credentials: Authentication?) async throws(KurrentError) -> ScopedCall<Response> }`
  - `Streams.Read`, `Streams.ReadAll` conform to `ScopedStreamResponse`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  LazyReadPathTests.swift
//  swift-kurrentdb
//
//  No server needed. Most tests point at 127.0.0.1:1 (ECONNREFUSED); the acceptance-cancel test
//  uses a local NIO listener that accepts TCP but never speaks HTTP/2, so the call really waits.
//  What is verified is which connection path was used and that every lease is returned.
//

import GRPCCore
import NIOCore
import NIOPosix
import Synchronization
import Testing
@testable import KurrentDB

/// Accepts TCP connections and never writes, so an RPC on it waits for acceptance forever.
private struct SilentListener {
    let channel: any Channel
    var port: Int { channel.localAddress!.port! }

    static func start() async throws -> SilentListener {
        let channel = try await ServerBootstrap(group: MultiThreadedEventLoopGroup.singleton)
            .bind(host: "127.0.0.1", port: 0)
            .get()
        return SilentListener(channel: channel)
    }

    func stop() async { try? await channel.close() }
}

@Suite("Lazy read path", .serialized, .timeLimit(.minutes(1)))
struct LazyReadPathTests {
    private static let refused = Endpoint(host: "127.0.0.1", port: 1)

    private func makeInfo(supporting descriptors: [GRPCCore.MethodDescriptor]) -> ServerFeatures.ServiceInfo {
        ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
    }

    private func makeNode(endpoint: Endpoint = refused, supporting descriptors: [GRPCCore.MethodDescriptor]) -> Node {
        let settings = ClientSettings.localhost()
        let provider = ConnectionProvider(settings: settings, idleTimeout: .seconds(3600), sweepInterval: nil)
        return Node(endpoint: endpoint, settings: settings, serverInfo: makeInfo(supporting: descriptors), connections: provider)
    }

    private var boundedCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(2)
        return options
    }

    // MARK: open(node:)

    @Test("open: a refused connection throws KurrentError on the shared path and returns the lease")
    func openRefusedReturnsLease() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.open(node: node, callOptions: boundedCallOptions, credentials: nil)
        }
        #expect(node.connections.createdSharedConnectionCount == 1)
        #expect(node.connections.createdDedicatedConnectionCount == 0)
        #expect(node.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("open: ReadAll takes the same path")
    func openReadAllRefused() async throws {
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: .init())
        let node = makeNode(supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }
        await #expect(throws: KurrentError.self) {
            _ = try await usecase.open(node: node, callOptions: boundedCallOptions, credentials: nil)
        }
        #expect(node.connections.createdSharedConnectionCount == 1)
        #expect(node.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("open: unsupported method throws unsupportedFeature without acquiring a lease")
    func openUnsupported() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(supporting: [])
        defer { node.connections.shutdown() }
        await #expect {
            _ = try await usecase.open(node: node, callOptions: boundedCallOptions, credentials: nil)
        } throws: { error in
            if case .unsupportedFeature = error as? KurrentError { return true }
            return false
        }
        #expect(node.connections.createdSharedConnectionCount == 0)
    }

    @Test("open: cancelling the caller while waiting for acceptance ends the call and returns the lease")
    func openCancelDuringAcceptance() async throws {
        let listener = try await SilentListener.start()
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let node = makeNode(endpoint: Endpoint(host: "127.0.0.1", port: listener.port), supporting: [usecase.methodDescriptor])
        defer { node.connections.shutdown() }

        let opener = Task {
            try await usecase.open(node: node, callOptions: .defaults, credentials: nil)   // no timeout: waits
        }
        try await Task.sleep(for: .milliseconds(300))
        opener.cancel()
        let outcome = await opener.result
        await listener.stop()

        await #expect {
            _ = try outcome.get()
        } throws: { error in
            if case .connectionClosed = error as? KurrentError { return true }
            return false
        }
        #expect(node.connections.sharedEntrySnapshot(for: Endpoint(host: "127.0.0.1", port: listener.port))?.retainCount == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --no-parallel --filter LazyReadPathTests`
Expected: FAIL to compile — `value of type 'Streams<SpecifiedStream>.Read' has no member 'open'`.

- [ ] **Step 3: Add the protocol** — append to `Sources/GRPCEncapsulates/ResponseHandlable.swift`:

```swift
/// A buffered stream usecase that can also hand its server-streaming call to a caller-owned
/// handler. KurrentDB's lazy read (`ReadCall.lazy`) drives the call from its own iterator.
///
/// `call` must invoke this usecase's generated client method and pass `onResponse` through
/// unchanged; the caller owns iteration, backpressure and the RPC's lifetime.
package protocol ScopedStreamResponse: UnaryStream, BufferedStreamResponse {
    func call<Result: Sendable>(
        connection: GRPCClient<Transport>,
        request: ClientRequest<UnderlyingRequest>,
        callOptions: CallOptions,
        onResponse: @Sendable @escaping (StreamingClientResponse<UnderlyingResponse>) async throws -> Result
    ) async throws -> Result
}
```

- [ ] **Step 4: Conform `Read` and `ReadAll`**

In `Streams.Read.swift` change the declaration to `public struct Read: UnaryStream, BufferedStreamResponse, ScopedStreamResponse {` and add inside the struct, after `send(...)`:

```swift
        package func call<Result: Sendable>(
            connection: GRPCClient<Transport>,
            request: ClientRequest<UnderlyingRequest>,
            callOptions: CallOptions,
            onResponse: @Sendable @escaping (StreamingClientResponse<UnderlyingResponse>) async throws -> Result
        ) async throws -> Result {
            try await ServiceClient(wrapping: connection).read(request: request, options: callOptions, onResponse: onResponse)
        }
```

Same in `Streams.ReadAll.swift` (`public struct ReadAll: UnaryStream, BufferedStreamResponse, ScopedStreamResponse {`, identical `call` body).

- [ ] **Step 5: Implement `UnaryStream+Scoped.swift`**

```swift
//
//  UnaryStream+Scoped.swift
//  KurrentCore
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Synchronization

/// One-shot signal: the server accepted the call (open) or the call failed before that (fail).
private final class AcceptanceGate: Sendable {
    private enum State {
        case pending(CheckedContinuation<Void, any Error>?)
        case opened
        case failed(any Error)
    }

    private let state = Mutex(State.pending(nil))

    func open() { resolve(.success(())) }
    func fail(_ error: any Error) { resolve(.failure(error)) }

    private func resolve(_ result: Result<Void, any Error>) {
        let waiter: CheckedContinuation<Void, any Error>? = state.withLock { state in
            guard case let .pending(waiter) = state else { return nil }
            switch result {
            case .success: state = .opened
            case let .failure(error): state = .failed(error)
            }
            return waiter
        }
        waiter?.resume(with: result)
    }

    func wait() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let immediate: Result<Void, any Error>? = state.withLock { state in
                    switch state {
                    case .pending:
                        state = .pending(continuation)
                        return nil
                    case .opened:
                        return .success(())
                    case let .failed(error):
                        return .failure(error)
                    }
                }
                if let immediate { continuation.resume(with: immediate) }
            }
        } onCancel: {
            fail(CancellationError())
        }
    }
}

/// An accepted server-streaming RPC: the task running it, its hand-off and its shared-connection
/// lease. Owned by a lazy read iterator.
package final class ScopedCall<Response: Sendable>: Sendable {
    package let handoff: ResponseHandoff<Response>
    private let lease: SharedLease
    private let task: Task<Void, Never>

    fileprivate init(handoff: ResponseHandoff<Response>, lease: SharedLease, task: Task<Void, Never>) {
        self.handoff = handoff
        self.lease = lease
        self.task = task
    }

    /// Ends the RPC and returns the lease, returning only after the RPC task has finished.
    /// Cancelling the task cancels only this RPC; the shared connection stays up for other calls.
    /// The order matters: cancelling the hand-off first makes the producer's exit quiet.
    package func close() async {
        handoff.cancel()
        task.cancel()
        await task.value
        lease.release()
    }

    /// `close()` for contexts that cannot await (an iterator's `deinit`): the lease is released
    /// once the RPC task has finished, from an unstructured task.
    package func closeInBackground() {
        handoff.cancel()
        task.cancel()
        let task = self.task
        let lease = self.lease
        Task {
            await task.value
            lease.release()
        }
    }
}

extension ScopedStreamResponse where Transport == HTTP2ClientTransport.Posix {
    /// Starts the RPC on the shared connection and returns once the server accepted it.
    ///
    /// A call the server rejects before accepting it (status-only response) or that fails to
    /// connect throws here, as `KurrentError`, with the lease already returned; `withRetry`
    /// callers may retry node failures because no element has been delivered yet. A caller
    /// cancelled while waiting gets `KurrentError.connectionClosed` (typed throws); the lazy
    /// iterator maps that to `CancellationError`.
    package func open(node: Node, callOptions: CallOptions, credentials: Authentication?) async throws(KurrentError) -> ScopedCall<Response> {
        guard node.serverInfo.isSupported(method: methodDescriptor) else {
            throw .unsupportedFeature(methodDescriptor)
        }

        let lease = try node.connections.acquire(node.endpoint)
        let request: ClientRequest<UnderlyingRequest>
        do {
            request = try withRethrowingError(usage: "\(Self.self).\(#function)") {
                try self.request(metadata: Metadata(from: node.settings, overriding: credentials))
            }
        } catch {
            lease.release()
            throw error
        }

        let handoff = ResponseHandoff<Response>()
        let accepted = AcceptanceGate()
        let task = Task {
            do {
                try await self.call(connection: lease.client, request: request, callOptions: callOptions) { response in
                    switch response.accepted {
                    case .success:
                        accepted.open()
                        // Same as the buffered send(): errors from the messages or from
                        // handle(message:) reach the consumer as they are.
                        do {
                            for try await message in response.messages {
                                try await handoff.send(self.handle(message: message))
                            }
                            handoff.finish()
                        } catch {
                            handoff.finish(throwing: error)
                        }
                    case let .failure(error):
                        accepted.fail(error)
                    }
                }
            } catch {
                // No-op for whichever side already resolved.
                accepted.fail(error)
                handoff.finish(throwing: error)
            }
        }

        let call = ScopedCall(handoff: handoff, lease: lease, task: task)
        do {
            try await withRethrowingError(usage: "\(Self.self).\(#function)") {
                try await accepted.wait()
            }
        } catch {
            await call.close()
            // A cancelled caller is not an internal failure; map it the way withRetry's backoff
            // does, so it is not retried.
            if Task.isCancelled { throw .connectionClosed }
            throw error
        }
        return call
    }
}
```

- [ ] **Step 6: Run tests**

Run: `for i in 1 2 3; do swift test --no-parallel --filter "LazyReadPathTests|UnaryStreamConnectionPathTests|ResponseHandoffTests" || break; done`
Expected: all PASS, 3 runs (`UnaryStreamConnectionPathTests` proves the buffered path is untouched). If `openCancelDuringAcceptance` hangs (suite time limit) or leaves `retainCount == 1`, report it — do not weaken the test.

- [ ] **Step 7: Commit**

```bash
git add Sources/GRPCEncapsulates/ResponseHandlable.swift Sources/KurrentDB/Core/Additions/Usecase/UnaryStream+Scoped.swift Sources/KurrentDB/Streams/Usecase/Specified/Streams.Read.swift Sources/KurrentDB/Streams/Usecase/All/Streams.ReadAll.swift Tests/MockClientTests/LazyReadPathTests.swift
git commit -m "[ADD] scoped call lifecycle for lazy reads on the shared connection"
```

---

### Task 4: `ReadCall`, `.lazy`, `.buffered`, the new `read` overloads

**Files:**
- Create: `Sources/KurrentDB/Streams/Streams.ReadCall.swift`
- Modify: `Sources/KurrentDB/Streams/API/Streams+SpecifiedStreamTarget.swift` (add overload after `read(configure:)` at ~line 127; add one `///` line to the existing `read`)
- Modify: `Sources/KurrentDB/Streams/API/Streams+AllStreamsTarget.swift` (same, ~line 18)
- Modify: `Tests/MockClientTests/LazyReadPathTests.swift` (second half)
- Create: `Tests/MockClientTests/ReadOverloadResolutionTests.swift`

**Interfaces:**
- Consumes: `ScopedCall`, `open(node:callOptions:credentials:)` (Task 3); `Streams.selector`, `.callOptions`, `.overrideCredentials`, `.identifier`; `Read(from:options:)`, `ReadAll(options:)`, `usecase.perform(selector:callOptions:credentials:)` (buffered path).
- Produces:
  - `extension Streams { public struct ReadCall: Sendable { public var lazy: Lazy { get }; public var buffered: AsyncThrowingStream<ReadResponse, any Error> { get async throws(KurrentError) } } }`
  - `ReadCall.Lazy: AsyncSequence, Sendable` (`Element == ReadResponse`), `ReadCall.Lazy.Iterator: AsyncIteratorProtocol` (final class)
  - `Streams where Target: SpecifiedStreamTarget`: `public func read(configure: @Sendable (inout Read.Options) -> Void = { _ in }) -> ReadCall`
  - `Streams where Target == AllStreamsTarget`: `public func read(configure: @Sendable (inout ReadAll.Options) -> Void = { _ in }) -> ReadCall`

- [ ] **Step 1: Write the failing tests** — append inside `LazyReadPathTests`:

```swift
    // MARK: ReadCall.lazy

    /// Seed and cached node both point at the refused port; retries are off.
    private func makeSelector(supporting descriptors: [GRPCCore.MethodDescriptor]) async -> NodeSelector {
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        let settings = ClientSettings(clusterMode: .standalone(endpoint: Self.refused)).operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        let node = Node(endpoint: Self.refused, settings: settings, serverInfo: makeInfo(supporting: descriptors), connections: selector.connections)
        await selector.cacheNodeForTesting(node)
        return selector
    }

    /// No cached node: the first call goes through node discovery.
    private func makeUncachedSelector() -> NodeSelector {
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        return NodeSelector(settings: ClientSettings(clusterMode: .standalone(endpoint: Self.refused)).operationRetryPolicy(policy))
    }

    private func makeStreams(_ selector: NodeSelector) -> Streams<SpecifiedStream> {
        Streams(target: .specified("any"), selector: selector, callOptions: boundedCallOptions)
    }

    @Test("lazy: a refused connection throws KurrentError at the first next(), shared path, lease returned")
    func lazyRefused() async throws {
        let selector = await makeSelector(supporting: [Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor])
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        await #expect(throws: KurrentError.self) {
            for try await _ in streams.read().lazy {}
        }
        #expect(selector.connections.createdSharedConnectionCount == 1)
        #expect(selector.connections.createdDedicatedConnectionCount == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("lazy: an iterator that is never advanced takes no lease")
    func droppedIteratorTakesNoLease() async throws {
        let selector = await makeSelector(supporting: [Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor])
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        do { _ = streams.read().lazy.makeAsyncIterator() }
        #expect(selector.connections.createdSharedConnectionCount == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused) == nil)
    }

    @Test("lazy: a caller that is already cancelled gets CancellationError before node discovery")
    func lazyPreCancelled() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let reader = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            for try await _ in streams.read().lazy {}
        }
        await #expect(throws: CancellationError.self) { try await reader.value }
        #expect(selector.connections.createdSharedConnectionCount == 0)
    }

    @Test("lazy: cancelling the caller during node discovery surfaces CancellationError")
    func lazyCancelDuringDiscovery() async throws {
        let selector = makeUncachedSelector()
        defer { selector.connections.shutdown() }
        let streams = makeStreams(selector)

        let reader = Task { for try await _ in streams.read().lazy {} }
        try await Task.sleep(for: .milliseconds(200))   // discovery against the refused port retries for ~1s
        reader.cancel()
        await #expect(throws: CancellationError.self) { try await reader.value }
    }

    @Test("lazy: cancelling the caller while waiting for acceptance surfaces CancellationError and returns the lease")
    func lazyCancelDuringAcceptance() async throws {
        let listener = try await SilentListener.start()
        let endpoint = Endpoint(host: "127.0.0.1", port: listener.port)
        var policy = OperationRetryPolicy.default
        policy.maxAttempts = 1
        let settings = ClientSettings(clusterMode: .standalone(endpoint: endpoint)).operationRetryPolicy(policy)
        let selector = NodeSelector(settings: settings)
        defer { selector.connections.shutdown() }
        let descriptor = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init()).methodDescriptor
        await selector.cacheNodeForTesting(Node(endpoint: endpoint, settings: settings, serverInfo: makeInfo(supporting: [descriptor]), connections: selector.connections))
        let streams = Streams<SpecifiedStream>(target: .specified("any"), selector: selector, callOptions: .defaults)

        let reader = Task { for try await _ in streams.read().lazy {} }
        try await Task.sleep(for: .milliseconds(300))
        reader.cancel()
        let outcome = await reader.result
        await listener.stop()

        await #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(selector.connections.sharedEntrySnapshot(for: endpoint)?.retainCount == 0)
    }
```

And the compile-level overload checks, `Tests/MockClientTests/ReadOverloadResolutionTests.swift`:

```swift
//
//  ReadOverloadResolutionTests.swift
//  swift-kurrentdb
//
//  Compile-level pins for the two `read(configure:)` overloads (spec §6). The closures below are
//  never executed; they exist so the compiler proves which overload each call shape resolves to.
//  If the ReadCall overload ever becomes `async`/`throws`, or ReadCall conforms to AsyncSequence,
//  these stop compiling — that is the point.
//

import Testing
@testable import KurrentDB

@Suite("read overload resolution")
struct ReadOverloadResolutionTests {
    private func acceptsOldStream(_: AsyncThrowingStream<Streams<SpecifiedStream>.ReadResponse, any Error>) {}
    private func acceptsOldAllStream(_: AsyncThrowingStream<Streams<AllStreamsTarget>.ReadResponse, any Error>) {}
    private func acceptsLazy(_: Streams<SpecifiedStream>.ReadCall.Lazy) {}
    private func acceptsCall(_: Streams<AllStreamsTarget>.ReadCall) {}

    @Test("Existing call shapes resolve to the buffered overload; member chains resolve to ReadCall")
    func shapes() {
        let client = MockKurrentDBClient()
        let specified = client.streams(specified: "orders")
        let all = client.allStreams

        // Existing shapes (never run; type-checked only).
        let _: () async throws -> Void = {
            acceptsOldStream(try await specified.read())
            acceptsOldStream(try await specified.read { $0.limit = 10 })
            acceptsOldAllStream(try await all.read())
            for try await _ in try await specified.read() {}
            let responses = try await all.read()
            for try await _ in responses {}
            _ = try await specified.read().reduce(0) { count, _ in count + 1 }
        }

        // New shapes.
        acceptsLazy(specified.read().lazy)
        acceptsLazy(specified.read { $0.limit = 10 }.lazy)
        acceptsCall(all.read())
        let call: Streams<SpecifiedStream>.ReadCall = specified.read()
        _ = call
        let _: () async throws -> Void = {
            for try await _ in specified.read().lazy {}
            for try await _ in try await all.read().buffered {}
            _ = try await specified.read().lazy.first { _ in true }
        }
        #expect(Bool(true))
    }
}
```

(`MockKurrentDBClient` lives in `Tests/MockClientTests/MockKurrentDBClient.swift` and returns real `Streams` values from its factories; check its initializer name and adapt the one line.)

- [ ] **Step 2: Run to verify failure**

Run: `swift build --build-tests`
Expected: FAIL — `value of type 'Streams<SpecifiedStream>.ReadCall' …` / `has no member 'lazy'` (no `ReadCall` yet).

- [ ] **Step 3: Implement `Streams.ReadCall.swift`**

```swift
//
//  Streams.ReadCall.swift
//  KurrentStreams
//

import GRPCCore

extension Streams {
    /// A read that has not started yet. Choose how its events are delivered:
    ///
    /// - ``lazy``: events are pulled from the server as you iterate, memory stays bounded, and
    ///   the RPC ends when the iterator is released.
    /// - ``buffered``: the whole result is fetched first, exactly like `read()`.
    ///
    /// ```swift
    /// for try await response in client.streams(specified: "orders").read().lazy { … }
    /// let total = try await client.allStreams.read { $0.limit = 1000 }.lazy.reduce(0) { $0 + 1 }
    /// ```
    ///
    /// Creating a `ReadCall` performs no network activity. It is deliberately **not** an
    /// `AsyncSequence` in 2.x, and the `read(configure:)` overload that returns it is synchronous
    /// and non-throwing: both are what keeps the existing `try await read()` call sites resolving
    /// to the buffered overload without ambiguity. To hold one in a variable without iterating,
    /// spell the type: `let call: Streams<SpecifiedStream>.ReadCall = stream.read()`.
    public struct ReadCall: Sendable {
        let selector: NodeSelector
        let openCall: @Sendable (Node) async throws(KurrentError) -> ScopedCall<ReadResponse>
        let bufferedRead: @Sendable () async throws(KurrentError) -> AsyncThrowingStream<ReadResponse, any Error>

        /// Events delivered as you iterate, with backpressure. Each iteration opens its own RPC.
        public var lazy: Lazy { Lazy(call: self) }

        /// The whole result, fetched before this returns. Identical to `read()`.
        public var buffered: AsyncThrowingStream<ReadResponse, any Error> {
            get async throws(KurrentError) { try await bufferedRead() }
        }
    }
}

extension Streams.ReadCall {
    /// The lazy form of a read: a cold sequence that opens one RPC per iterator.
    ///
    /// The RPC ends when the iterator is released — after the loop finishes, on `break`, on a
    /// thrown error, or when the iterating task is cancelled. Memory is bounded by the hand-off
    /// capacity plus one HTTP/2 stream flow-control window. The only way to keep the RPC open is
    /// to call `makeAsyncIterator()` yourself and hold on to the iterator.
    public struct Lazy: AsyncSequence, Sendable {
        public typealias Element = Streams.ReadResponse
        public typealias Failure = any Error

        let call: Streams.ReadCall

        public func makeAsyncIterator() -> Iterator { Iterator(call: call) }

        public final class Iterator: AsyncIteratorProtocol {
            private let call: Streams.ReadCall
            private var scoped: ScopedCall<Streams.ReadResponse>?
            private var finished = false

            init(call: Streams.ReadCall) { self.call = call }

            deinit {
                // The loop ended without reaching the end (break, throw, cancellation, or the
                // iterator was dropped): end the RPC and return the lease in the background.
                if let scoped, !finished { scoped.closeInBackground() }
            }

            public func next() async throws -> Streams.ReadResponse? {
                if finished { return nil }
                try Task.checkCancellation()

                let active: ScopedCall<Streams.ReadResponse>
                if let scoped {
                    active = scoped
                } else {
                    // Retry covers only establishing the call: no element has been delivered yet.
                    do {
                        active = try await withRetry(
                            policy: call.selector.retryPolicy,
                            selectNode: { try await call.selector.select() },
                            invalidate: { await call.selector.invalidate() }
                        ) { node in
                            try await call.openCall(node)
                        }
                    } catch {
                        // Node discovery wraps a cancelled task as internalClientError and open()
                        // as connectionClosed; the caller asked to stop either way.
                        if Task.isCancelled { throw CancellationError() }
                        throw error
                    }
                    scoped = active
                }

                do {
                    if let element = try await active.handoff.next() { return element }
                    // Either the server finished the stream or our task was cancelled (the
                    // hand-off ends quietly on consumer-side cancellation).
                    finished = true
                    await active.close()
                    try Task.checkCancellation()
                    return nil
                } catch {
                    finished = true
                    await active.close()
                    throw error
                }
            }
        }
    }
}
```

- [ ] **Step 4: Add the overloads**

In `Streams+SpecifiedStreamTarget.swift`, right after the existing `read(configure:)`:

```swift
    /// Prepares a read whose delivery you choose with ``ReadCall/lazy`` or ``ReadCall/buffered``.
    /// Nothing happens until one of them is used.
    ///
    /// ```swift
    /// for try await response in client.streams(specified: "orders").read().lazy {
    ///     print(try response.event.record.eventType)
    /// }
    /// ```
    ///
    /// - Parameter configure: Configures ``Read/Options`` (direction, limit, starting revision). Defaults to no-op.
    public func read(configure: @Sendable (inout Read.Options) -> Void = { _ in }) -> ReadCall {
        var options = Read.Options()
        configure(&options)
        let usecase = Read(from: identifier, options: options)
        let selector = selector, callOptions = callOptions, credentials = overrideCredentials
        return ReadCall(
            selector: selector,
            openCall: { node throws(KurrentError) in try await usecase.open(node: node, callOptions: callOptions, credentials: credentials) },
            bufferedRead: { () throws(KurrentError) in try await usecase.perform(selector: selector, callOptions: callOptions, credentials: credentials) }
        )
    }
```

and add this line to the existing buffered `read`'s `///`, after its first sentence: `/// The whole result is fetched before this returns, so memory grows with the result; this is the same as ``ReadCall/buffered``. For large reads use ``read(configure:)-<hash>`` with ``ReadCall/lazy``.` (If DocC cannot resolve the overload link, write plain code font: `read().lazy`.)

Same in `Streams+AllStreamsTarget.swift` with `ReadAll.Options`, `ReadAll(options: options)` and the `$all` wording.

If the typed-throws closure spelling (`{ node throws(KurrentError) in … }`) does not compile on your toolchain, declare the stored closure types as untyped `async throws` and wrap with `withRethrowingError`-style casting inside `Iterator.next()`; note the deviation.

- [ ] **Step 5: Run tests**

Run: `for i in 1 2 3; do swift test --no-parallel --filter "LazyReadPathTests|ReadOverloadResolutionTests|UnaryStreamConnectionPathTests|ResponseHandoffTests" || break; done`
Expected: all PASS, 3 runs.

- [ ] **Step 6: Commit**

```bash
git add Sources/KurrentDB/Streams/Streams.ReadCall.swift Sources/KurrentDB/Streams/API/Streams+SpecifiedStreamTarget.swift Sources/KurrentDB/Streams/API/Streams+AllStreamsTarget.swift Tests/MockClientTests/LazyReadPathTests.swift Tests/MockClientTests/ReadOverloadResolutionTests.swift
git commit -m "[ADD] ReadCall with lazy and buffered delivery"
```

---

### Task 5: Live behaviour of `.lazy`

**Files:**
- Modify: `Tests/StreamsTests/LazyReadLiveTests.swift` (add tests; keep the spike)

**Interfaces:**
- Consumes: public `read().lazy` / `.buffered` (Task 4); `sharedRetainCount`, `eventually`, `appendEvents` (Task 1).

- [ ] **Step 1: Add the tests** inside `LazyReadLiveTests`:

```swift
    @Test("lazy returns the same events as read() and as buffered")
    func lazyMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 50, to: stream)

        let viaRead = try await stream.read().reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        let viaBuffered = try await stream.read().buffered.reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        let viaLazy = try await stream.read().lazy.reduce(into: [UUID]()) { $0.append(try $1.event.record.id) }
        #expect(viaLazy == viaRead)
        #expect(viaBuffered == viaRead)
        #expect(viaLazy.count == 50)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("Breaking after the first event returns the lease and production stays bounded")
    func earlyBreakReleasesLease() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        var iterator = stream.read().lazy.makeAsyncIterator()
        let first = try await iterator.next()
        #expect(first != nil)
        #expect(try await sharedRetainCount(client) == 1)             // positive control: the lease is held
        try await Task.sleep(for: .milliseconds(500))
        // The RPC task feeds a capacity-1 hand-off; nothing is pulled, so production has stalled.
        // Observe through a second lazy iteration whose counters we can read: open directly.
        let node = try await client.selector.select()
        let usecase = Streams<SpecifiedStream>.Read(from: stream.identifier, options: .init())
        let call = try await usecase.open(node: node, callOptions: .defaults, credentials: nil)
        _ = try await call.handoff.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(call.handoff.sentCount - call.handoff.deliveredCount <= call.handoff.capacity)
        #expect(call.handoff.sentCount < 300)
        await call.close()

        iterator = stream.read().lazy.makeAsyncIterator()   // release the first iterator → its RPC ends
        _ = iterator
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("A Lazy value can be iterated twice; each iteration is its own RPC")
    func lazyIsReiterable() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 20, to: stream)
        let lazy = stream.read().lazy

        var firstRun = 0
        for try await _ in lazy { firstRun += 1; if firstRun == 3 { break } }
        var secondRun = 0
        for try await _ in lazy { secondRun += 1 }
        #expect(firstRun == 3)
        #expect(secondRun == 20)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("Cancelling the iterating task throws CancellationError and returns the lease")
    func callerCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        let (firstElement, signal) = AsyncStream.makeStream(of: Void.self)
        let reader = Task {
            defer { signal.finish() }
            var count = 0
            for try await _ in stream.read().lazy {
                count += 1
                if count == 1 { signal.yield() }
                try? await Task.sleep(for: .milliseconds(50))   // non-throwing wait: cancellation must come from the SDK
            }
            return count
        }
        for await _ in firstElement { break }
        reader.cancel()
        await #expect(throws: CancellationError.self) { _ = try await reader.value }
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("A missing stream fails during iteration with the same error as read(), then ends")
    func missingStreamMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-missing-\(UUID().uuidString)")

        var bufferedError: (any Error)?
        do { for try await _ in try await stream.read() {} } catch { bufferedError = error }

        var lazyError: (any Error)?
        var iterator = stream.read().lazy.makeAsyncIterator()
        do { _ = try await iterator.next() } catch { lazyError = error }
        let afterError = try await iterator.next()

        #expect(bufferedError != nil)
        #expect(lazyError.map { "\($0)" } == bufferedError.map { "\($0)" })
        #expect(afterError == nil)
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("Wrong credentials fail at the first next(), before any element")
    func wrongCredentials() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 5, to: stream)

        let unauthorised = stream.authenticated(.credentials(username: "admin", password: "wrong-password"))
        await #expect(throws: KurrentError.self) {
            for try await _ in unauthorised.read().lazy {}
        }
        #expect(try await eventually { (try? await sharedRetainCount(client)) == 0 })
    }

    @Test("$all lazy read honours the limit")
    func allStreamsLazy() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let count = try await client.allStreams.read { $0.limit = 5 }.lazy.reduce(0) { total, _ in total + 1 }
        #expect(count == 5)
    }

    @Test("After shutdown, the first next() throws connectionClosed")
    func afterShutdown() async throws {
        let client = KurrentDBClient(settings: settings)
        let stream = client.streams(specified: "LazyRead-\(UUID().uuidString)")
        try await appendEvents(count: 1, to: stream)
        try client.shutdown()
        await #expect(throws: KurrentError.connectionClosed) {
            for try await _ in stream.read().lazy {}
        }
    }
```

- [ ] **Step 2: Run**

Run: `for i in 1 2 3; do swift test --no-parallel --filter LazyReadLiveTests || break; done`
Expected: 9 tests PASS, 3 runs. If `afterShutdown` surfaces a different `KurrentError` case, report the actual case (the buffered `read()` after `shutdown()` throws `connectionClosed` today — see `ConnectionReuseLiveTests`); do not loosen the assertion silently.

- [ ] **Step 3: Commit**

```bash
git add Tests/StreamsTests/LazyReadLiveTests.swift
git commit -m "[ADD] live tests for lazy read lifecycle"
```

---

### Task 6: Subscription backpressure

**Files:**
- Modify: `Sources/KurrentDB/Streams/Streams.Subscription.swift`
- Modify: `Sources/KurrentDB/Streams/Usecase/Specified/Streams.Subscribe.swift` (`send` ~lines 50–75, `Subscription.init(messages:)` ~lines 205–243)
- Modify: `Sources/KurrentDB/Streams/Usecase/All/Streams.SubscribeAll.swift` (`send` ~45–70, `init(messages:)` ~212–249)
- Create: `Tests/StreamsTests/SubscriptionBackpressureLiveTests.swift`

**Interfaces:**
- Consumes: `ResponseHandoff` (Task 2).
- Produces: `Streams.Subscription` with `package let messages: ResponseHandoff<Read.UnderlyingResponse>` and `package init(events:subscriptionId:messages:)`; public `events`, `subscriptionId`, `cancel()` unchanged.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  SubscriptionBackpressureLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml.
//

import Foundation
@testable import KurrentDB
import Testing

@Suite("Subscription backpressure (live)", .serialized, .timeLimit(.minutes(3)))
struct SubscriptionBackpressureLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func events(_ n: Int) -> [EventData] {
        (0 ..< n).map { _ in EventData(eventType: "Backpressure-Test", model: ["Description": "backpressure"]) }
    }

    private func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test("A slow consumer keeps the client-side buffer bounded")
    func slowConsumerIsBounded() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "Backpressure-\(UUID().uuidString)")
        _ = try await stream.append(events: events(300)) { $0.expectedRevision = .any }

        let subscription = try await stream.subscribe { $0.revision = .start }   // default is .end
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .milliseconds(500))

        #expect(subscription.messages.sentCount - subscription.messages.deliveredCount <= subscription.messages.capacity)
        #expect(subscription.messages.sentCount < 100)
        subscription.cancel()
    }

    @Test("cancel() while the consumer waits ends the loop and closes the dedicated connection")
    func cancelWhileWaiting() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "Backpressure-\(UUID().uuidString)")
        _ = try await stream.append(events: events(1)) { $0.expectedRevision = .any }

        let subscription = try await stream.subscribe { $0.revision = .start }
        let consumer = Task {
            var count = 0
            for try await _ in subscription.events { count += 1 }
            return count
        }
        #expect(try await eventually { subscription.messages.deliveredCount >= 2 })   // event + caughtUp consumed
        #expect(client.selector.connections.activeDedicatedConnectionCount == 1)

        subscription.cancel()
        #expect(try await consumer.value == 1)
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
    }

    @Test("$all subscription keeps the buffer bounded too")
    func allStreamsSlowConsumer() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let filler = client.streams(specified: "Backpressure-filler-\(UUID().uuidString)")
        _ = try await filler.append(events: events(300)) { $0.expectedRevision = .any }

        let subscription = try await client.allStreams.subscribe { $0.position = .start }
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(subscription.messages.sentCount - subscription.messages.deliveredCount <= subscription.messages.capacity)
        #expect(subscription.messages.sentCount < 100)
        subscription.cancel()
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift build --build-tests`
Expected: FAIL — `value of type 'Streams<SpecifiedStream>.Subscription' has no member 'messages'`.

- [ ] **Step 3: Rewrite `Streams.Subscription`** (replace the struct body in `Streams.Subscription.swift`):

```swift
extension Streams {
    /// Live subscription to a stream, delivering events as an async throwing stream.
    public struct Subscription: Sendable {
        /// Async throwing stream of events received from the server.
        public let events: AsyncThrowingStream<ReadEvent, Error>

        /// Server-assigned identifier for this subscription, if provided.
        public let subscriptionId: String?

        /// Bounded hand-off between the gRPC response handler and ``events``.
        package let messages: ResponseHandoff<Read.UnderlyingResponse>

        package init(events: AsyncThrowingStream<ReadEvent, Error>, subscriptionId: String?, messages: ResponseHandoff<Read.UnderlyingResponse>) {
            self.events = events
            self.subscriptionId = subscriptionId
            self.messages = messages
        }

        /// Cancels the subscription and terminates the event stream.
        public func cancel() {
            messages.cancel()
        }
    }
}
```

- [ ] **Step 4: Rewrite `Subscribe.send` and `Subscription.init(messages:)`** in `Streams.Subscribe.swift`:

```swift
        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?) -> Void) async throws -> Responses {
            let messages = ResponseHandoff<UnderlyingResponse>(onTermination: completion)

            Task {
                do {
                    let client = ServiceClient(wrapping: connection)
                    try await client.read(request: request, options: callOptions) {
                        // An infinite loop must be executed inside the `onResponse` closure; if you leave the onResponse closure, the connection will end.
                        for try await message in $0.messages.cancelOnGracefulShutdown() {
                            try await messages.send(message)
                        }
                        messages.finish()
                    }
                } catch {
                    messages.finish(throwing: error)
                }
            }
            return try await .init(messages: messages)
        }
```

```swift
extension Streams.Subscription where Target: SpecifiedStreamTarget {
    package init(messages: ResponseHandoff<Streams.Subscribe.UnderlyingResponse>) async throws {
        let first: Streams.Subscribe.UnderlyingResponse?
        do {
            first = try await messages.next()
        } catch {
            messages.cancel()
            throw error
        }
        guard case let .confirmation(confirmation) = first?.content else {
            messages.cancel()
            throw KurrentError.subscriptionTerminated(subscriptionId: nil)
        }

        let events = messages.makeStream { message -> ReadEvent? in
            switch message.content {
            case let .event(value):
                return try ReadEvent(message: value)
            case .caughtUp:
                logger.debug("[Streams.Subscribe] Subscription caught up with the stream.")
                return nil
            case let content?:
                logger.debug("[Streams.Subscribe] Received non-event subscription message: \(content)")
                return nil
            case nil:
                return nil
            }
        }
        self.init(events: events, subscriptionId: confirmation.subscriptionID, messages: messages)
    }
}
```

- [ ] **Step 5: Same for `SubscribeAll`** in `Streams.SubscribeAll.swift` — `send` identical to Step 4; `init(messages:)` identical except the extension constraint `where Target == AllStreamsTarget`, the type `Streams.SubscribeAll.UnderlyingResponse`, and the log prefix `[Streams.SubscribeAll]` / "caught up with the $all stream". (`SubscribeAll.UnderlyingResponse` is `ReadAll.UnderlyingResponse`, the same generated `ReadResp` type as `Read.UnderlyingResponse`; if the compiler disagrees, spell the stored property's type as `UnderlyingClient.UnderlyingService.Method.Read.Output`.)

- [ ] **Step 6: Run**

Run: `for i in 1 2 3; do swift test --no-parallel --filter "SubscriptionBackpressureLiveTests|StreamsTests|AllStreamsTargetTests|ConnectionReuseLiveTests" || break; done` and `swift build --target KurrentDB_V1`
Expected: all PASS, 3 runs; V1 builds. (`testSubscribeAllExcludeSystemEvents` in `StreamsTests` is a known cross-writer race on the shared cluster — if it fails, rerun it in isolation and report; it is unrelated to this change.)

- [ ] **Step 7: Commit**

```bash
git add Sources/KurrentDB/Streams/Streams.Subscription.swift Sources/KurrentDB/Streams/Usecase/Specified/Streams.Subscribe.swift Sources/KurrentDB/Streams/Usecase/All/Streams.SubscribeAll.swift Tests/StreamsTests/SubscriptionBackpressureLiveTests.swift
git commit -m "[UPDATE] bound subscription buffering with a backpressured hand-off"
```

---

### Task 7: Documentation

**Files:**
- Modify: `Sources/KurrentDB/KurrentDB.docc/Articles/Reading events.md` (new sections before `## Architecture`)
- Modify: `README.md` (one line beside the read example)

- [ ] **Step 1: Add to `Reading events.md`**, before `## Architecture`:

````markdown
## Bounded memory: `read().lazy`

`read()` fetches the whole result before it returns, so memory grows with the result. For large
reads use the lazy form: events arrive as you iterate, memory is bounded by a small hand-off plus
one HTTP/2 flow-control window, and the RPC ends when the loop does.

```swift
var total = 0.0
for try await response in client.streams(specified: "orders").read().lazy {
    if let order = try response.event.record.decode(to: OrderPlaced.self) {
        total += order.total
    }
}
```

`lazy` is an `AsyncSequence`, so the usual operations apply and stop the RPC as soon as they are
done:

```swift
let cancelled = try await client.allStreams.read().lazy.first {
    try $0.event.record.eventType == "OrderCancelled"
}
let count = try await client.streams(specified: "orders").read { $0.limit = 1000 }.lazy.reduce(0) { n, _ in n + 1 }
```

The RPC ends when the iterator is released: after the loop, on `break`, on a thrown error, or when
your task is cancelled (`next()` then throws `CancellationError`). Only an iterator you obtain with
`makeAsyncIterator()` and keep keeps the RPC open. A call the server rejects before accepting it
(for example bad credentials) fails at the first element and follows the client's retry policy;
later errors, including a missing stream, surface while you iterate, as with `read()`.

`read().buffered` is the explicit spelling of what `read()` does today:

```swift
let responses = try await client.streams(specified: "orders").read { $0.limit = 10 }.buffered
```

To hold a prepared read without iterating, spell its type: `let call: Streams<SpecifiedStream>.ReadCall = stream.read()`.

### Roadmap

In 3.0 `read()` itself delivers lazily; code that needs the whole result up front will write
`.buffered`. See `docs/adr/0001-read-becomes-lazy-in-3-0.md`. Subscriptions already apply the same
backpressure: a slow consumer pauses the server instead of growing client memory.
````

If `decode(to:)` is not the article's decoding spelling, use whatever the "Reading forwards" section uses so the snippet compiles.

- [ ] **Step 2: README** — next to the existing read example, add one line:

```swift
// Bounded memory: events arrive as you iterate and the RPC ends with the loop
for try await response in client.streams(specified: "orders").read().lazy { … }
```

(Keep README snippets compiling: `scripts/generate-doc-snippets.py` compiles README too; use real statements, e.g. `_ = response`.)

- [ ] **Step 3: Compile every documentation example**

Run: `scripts/check-doc-snippets.sh`
Expected: exit 0.

- [ ] **Step 4: Commit**

```bash
git add "Sources/KurrentDB/KurrentDB.docc/Articles/Reading events.md" README.md
git commit -m "[UPDATE] document read().lazy and read().buffered"
```

---

### Task 8: Full verification

- [ ] **Step 1: Offline suites** — `swift test --no-parallel --filter "MockClientTests|KurrentCoreTests"` → all PASS.
- [ ] **Step 2: Full live run** (cluster running) — `swift test -v --no-parallel --disable-xctest --enable-swift-testing` → all PASS; record skipped suites (`X509Tests` without license, `KurrentDBPool Live Tests`, env-gated `AppendRecords`).
- [ ] **Step 3: Flakiness** — `for i in 1 2 3 4 5; do swift test --no-parallel --filter "ResponseHandoffTests|LazyReadPathTests|LazyReadLiveTests|SubscriptionBackpressureLiveTests" || break; done` → 5 clean runs.
- [ ] **Step 4: Swift 6.0** — on a clean worktree (`git worktree add --detach <scratch>/wt60 HEAD`), `docker run --rm --platform linux/arm64 -v <scratch>/wt60:/w -w /w swift:6.0-jammy swift build --build-tests` → `Build complete`, no errors. Remove the worktree afterwards.
- [ ] **Step 5: Docs** — `scripts/check-doc-snippets.sh` exit 0; `swift build --target KurrentDB_V1` builds.
- [ ] **Step 6: Record** — append a "## Review" section to this plan (commands, counts, skips, Swift 6.0 result) and commit: `[UPDATE] record verification results for ReadCall`.

## Review

Verified at 87b74d43 against the local 3-node cluster (2111-2113).

1. Offline (`swift test --no-parallel --filter "MockClientTests|KurrentCoreTests"`):
   - `✔ Test run with 75 tests in 7 suites passed after 0.919 seconds.`
   - `✔ Test run with 149 tests in 13 suites passed after 0.039 seconds.`
2. Full live run (`swift test -v --no-parallel --disable-xctest --enable-swift-testing`), exit 0, no failures:
   - `✔ Test run with 80 tests in 10 suites passed after 84.771 seconds.`
   - `✔ Test run with 16 tests in 2 suites passed after 12.775 seconds.`
   - `✔ Test run with 20 tests in 4 suites passed after 15.997 seconds.`
   - `✔ Test run with 75 tests in 7 suites passed after 0.909 seconds.`
   - `✔ Test run with 11 tests in 2 suites passed after 0.478 seconds.`
   - `✔ Test run with 149 tests in 13 suites passed after 0.034 seconds.`
   - (plus 6 smaller runs of 1-7 tests, all passed)
   - Skipped as expected: `X509Tests` (no license), `AppendRecords (DCB) Tests` (env-gated), `KurrentDBPool Live Tests` (independent instances).
3. Flakiness loop x5 (`ResponseHandoffTests|LazyReadPathTests|LazyReadLiveTests|SubscriptionBackpressureLiveTests`): 5/5 clean, each run
   `✔ Test run with 13 tests in 2 suites passed after ~3.1 seconds.` and `✔ Test run with 25 tests in 2 suites passed after ~0.87 seconds.`
4. Swift 6.0 (`swift:6.0-jammy`, linux/arm64, clean worktree): `Build complete! (138.26s)`; no errors, no ReadCall/ResponseHandoff/Scoped/LazyRead warnings. Worktree removed.
5. Docs: `scripts/check-doc-snippets.sh` exit 0 (`wrote 190 snippets`); `swift build --target KurrentDB_V1` -> `Build complete! (1.81 sec)`.
