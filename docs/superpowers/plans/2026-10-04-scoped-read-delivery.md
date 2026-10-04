# Scoped Read Delivery & Subscription Backpressure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `streams(...).delivery(.scoped).read { options } body: { events in }` — a read whose memory is bounded and whose RPC is guaranteed finished (lease returned) when `body` returns — and replace the unbounded buffers in `Subscribe`/`SubscribeAll` with a backpressured hand-off.

**Architecture:** A package-level single-producer/single-consumer `ResponseHandoff<Element>` (fixed capacity, `Mutex` + `CheckedContinuation`) carries messages from the gRPC response handler to the consumer, so HTTP/2 flow control pushes back on the server. The scoped read opens the RPC on the shared connection lease inside a `Task`, waits until the server accepts the call (retry applies up to here), runs the caller's `body`, then cancels the task, awaits it and releases the lease. Subscriptions keep their dedicated connection and public types; only the internal buffering changes.

**Tech Stack:** Swift 6.0+, grpc-swift 2 (`GRPCCore`), `Synchronization.Mutex`, Swift Testing. Live tests need the 3-node TLS cluster (`server/docker-compose.yaml`, ports 2111–2113).

**Spec:** `docs/superpowers/specs/2026-10-04-scoped-read-delivery-design.md`

## Global Constraints

- Swift 6.0 or later; platforms as in `Package.swift` (macOS 15+ — `Synchronization.Mutex` is available).
- No new package dependencies.
- No public API breaks: `read()`, `Subscription.events`, `Subscription.subscriptionId`, `Subscription.cancel()`, `KurrentDBClientProtocol` keep their exact signatures.
- The existing `read()` is not deprecated in this plan (no `@available(*, deprecated)`).
- All `//` and `///` comments in English.
- Commit messages: `[TAG] short description in English` (`[ADD]`, `[UPDATE]`, `[FIX]`, `[REFACTOR]`, …). **No `Co-Authored-By:` lines.**
- Public scoped `read` uses untyped `throws` (body errors propagate unchanged); SDK-internal setup errors are still `KurrentError`.
- Retry covers only what happens before `body` is invoked.
- Naming: axis `delivery`, protocol `ResponseDelivery`, value type `ScopedDelivery`, static member `.scoped`, wrapper `ScopedStreams<Target>`.

## Review Focus

1. Consumer `break`s after the first event (body returns before draining) → `read` returns, the RPC is cancelled, `retainCount` is back to 0, and a concurrent RPC on the same shared connection is unaffected. (Tasks 1, 4)
2. `body` throws its own error → the very same error value reaches the caller (not wrapped in `KurrentError`) and the lease is released. (Task 4)
3. The caller's task is cancelled while `body` is iterating → `read` finishes promptly and the lease is released. (Task 4)
4. The stream escapes `body` and is iterated after `read` returned → iteration ends immediately with no element and no hang. (Task 4)
5. `Subscription.cancel()` while the consumer is suspended waiting for the next event → the `for try await` loop ends and the dedicated connection is closed. (Task 5)

---

## File Structure

| File | Responsibility |
|---|---|
| Create `Sources/KurrentDB/Core/ResponseHandoff.swift` | Bounded SPSC hand-off + `makeStream` with cancel-on-deinit sentinel |
| Modify `Sources/GRPCEncapsulates/ResponseHandlable.swift` | Add `ScopedStreamResponse` protocol |
| Create `Sources/KurrentDB/Core/Additions/Usecase/UnaryStream+Scoped.swift` | `AcceptanceGate`, `ScopedCall`, `open(node:)`, `performScoped(selector:)` |
| Modify `Sources/KurrentDB/Streams/Usecase/Specified/Streams.Read.swift` | Conform to `ScopedStreamResponse` |
| Modify `Sources/KurrentDB/Streams/Usecase/All/Streams.ReadAll.swift` | Conform to `ScopedStreamResponse` |
| Create `Sources/KurrentDB/Core/ResponseDelivery.swift` | `ResponseDelivery`, `ScopedDelivery`, `.scoped` |
| Create `Sources/KurrentDB/Streams/API/Streams+ScopedDelivery.swift` | `delivery(_:)`, `ScopedStreams`, scoped `read` for specified / `$all` |
| Modify `Sources/KurrentDB/Streams/Streams.Subscription.swift` | Hold the hand-off instead of continuation + task |
| Modify `Sources/KurrentDB/Streams/Usecase/Specified/Streams.Subscribe.swift` | Hand-off in `send()` and `Subscription.init(messages:)` |
| Modify `Sources/KurrentDB/Streams/Usecase/All/Streams.SubscribeAll.swift` | Same as above for `$all` |
| Create `Tests/MockClientTests/ResponseHandoffTests.swift` | Offline unit tests for the hand-off |
| Create `Tests/MockClientTests/ScopedReadPathTests.swift` | Offline tests for the scoped path (refused port) |
| Create `Tests/StreamsTests/ScopedReadLiveTests.swift` | Live tests: shared-connection isolation, scoped read behaviour |
| Create `Tests/StreamsTests/SubscriptionBackpressureLiveTests.swift` | Live tests: subscription backpressure and cancel |
| Modify `Sources/KurrentDB/KurrentDB.docc/Articles/Reading events.md` | Document scoped delivery |
| Modify `CLAUDE.md` | Record the type-axis vs options rule |

Start the cluster once before live tasks:

```bash
docker compose -f server/docker-compose.yaml up -d
```

---

### Task 1: Spike — cancelling one RPC leaves the shared connection intact

The scoped path relies on this. If the test fails, **stop**: report back, and the scoped path (Task 3) must use `node.connections.openDedicated(for:)` instead of `acquire(_:)`.

**Files:**
- Create: `Tests/StreamsTests/ScopedReadLiveTests.swift`

**Interfaces:**
- Consumes: `client.selector.select() async throws(KurrentError) -> Node`, `node.connections.acquire(_:) -> SharedLease`, `SharedLease.client`, `SharedLease.release()`, `ConnectionProvider.createdSharedConnectionCount`, `Streams<SpecifiedStream>.UnderlyingClient` (the generated `EventStore_Client_Streams_Streams.Client`).
- Produces: the test suite file `ScopedReadLiveTests` with helpers `settings`, `event(_:)`, `eventually(timeout:_:)`, `appendEvents(count:to:)` reused by Task 4.

- [ ] **Step 1: Write the test**

```swift
//
//  ScopedReadLiveTests.swift
//  swift-kurrentdb
//
//  Needs the 3-node cluster from server/docker-compose.yaml.
//

import Foundation
import GRPCCore
@testable import KurrentDB
import Testing

@Suite("Scoped read (live)", .serialized, .timeLimit(.minutes(3)))
struct ScopedReadLiveTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
            .secure(true)
            .tlsVerifyCert(false)
            .authenticated(.credentials(username: "admin", password: "changeit"))
            .certificate(source: .crtInBundle("ca", inBundle: .module)!)
    }

    private func event(_ type: String = "ScopedRead-Test") -> EventData {
        EventData(eventType: type, model: ["Description": "scoped read"])
    }

    /// Waits until the condition holds or the timeout passes.
    private func eventually(timeout: Duration = .seconds(10), _ condition: () -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    private func appendEvents(count: Int, to stream: Streams<SpecifiedStream>) async throws {
        _ = try await stream.append(events: (0 ..< count).map { _ in event() }) { $0.expectedRevision = .any }
    }

    @Test("Cancelling one server-streaming RPC does not disturb another on the same shared connection")
    func cancellingOneRPCKeepsSharedConnection() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "ScopedRead-Spike-\(UUID().uuidString)"
        let stream = client.streams(specified: name)
        try await appendEvents(count: 200, to: stream)

        let node = try await client.selector.select()
        let createdBefore = client.selector.connections.createdSharedConnectionCount
        let lease = try node.connections.acquire(node.endpoint)
        defer { lease.release() }

        let request = ClientRequest(
            message: try Streams<SpecifiedStream>.Read(from: .init(name: name), options: .init()).requestMessage(),
            metadata: try Metadata(from: node.settings)
        )

        // RPC A: read one message, then park until cancelled.
        let parked = Task {
            let service = Streams<SpecifiedStream>.UnderlyingClient(wrapping: lease.client)
            try await service.read(request: request) { response in
                var iterator = response.messages.makeAsyncIterator()
                _ = try await iterator.next()
                try await Task.sleep(for: .seconds(60))
            }
        }

        // RPC B runs on the same shared connection while A is parked, and again after A is cancelled.
        let before = try await stream.read().reduce(0) { count, _ in count + 1 }
        parked.cancel()
        _ = await parked.result
        let after = try await stream.read().reduce(0) { count, _ in count + 1 }

        #expect(before == 200)
        #expect(after == 200)
        #expect(client.selector.connections.createdSharedConnectionCount == createdBefore)
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter ScopedReadLiveTests/cancellingOneRPCKeepsSharedConnection`
Expected: PASS. If `createdSharedConnectionCount` grew or `after != 200`, stop and report (see task intro).

- [ ] **Step 3: Commit**

```bash
git add Tests/StreamsTests/ScopedReadLiveTests.swift
git commit -m "[ADD] live spike test: cancelling one RPC keeps the shared connection"
```

---

### Task 2: `ResponseHandoff`

**Files:**
- Create: `Sources/KurrentDB/Core/ResponseHandoff.swift`
- Test: `Tests/MockClientTests/ResponseHandoffTests.swift`

**Interfaces:**
- Produces:
  - `package final class ResponseHandoff<Element: Sendable>: Sendable`
  - `init(capacity: Int = 1, onTermination: @escaping @Sendable ((any Error)?) -> Void = { _ in })` — `capacity >= 1`
  - `func send(_ element: Element) async throws` — suspends while full; throws `CancellationError` once cancelled
  - `func next() async throws -> Element?`
  - `func finish(throwing error: (any Error)? = nil)` — producer side, idempotent
  - `func cancel()` — consumer side, idempotent; drops buffer, wakes producer with `CancellationError`
  - `func makeStream() -> AsyncThrowingStream<Element, any Error>`
  - `func makeStream<T: Sendable>(_ transform: @escaping @Sendable (Element) throws -> T?) -> AsyncThrowingStream<T, any Error>` — `nil` skips the element
  - `var sentCount: Int`, `var deliveredCount: Int` — accepted from the producer / handed to the consumer
  - `onTermination` fires exactly once, on the first of `finish` (with its error) or `cancel` (with `nil`).

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

/// Counts onTermination calls.
private final class TerminationProbe: Sendable {
    private let calls = Mutex<[String]>([])
    var count: Int { calls.withLock { $0.count } }
    var last: String? { calls.withLock { $0.last } }
    func record(_ error: (any Error)?) { calls.withLock { $0.append(error.map { "\($0)" } ?? "nil") } }
}

@Suite("ResponseHandoff", .timeLimit(.minutes(1)))
struct ResponseHandoffTests {
    /// Yields enough times for spawned tasks to reach their next suspension point.
    private func settle() async {
        for _ in 0 ..< 200 { await Task.yield() }
    }

    @Test("Delivers in order and ends with nil after finish")
    func deliversInOrder() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 2)
        let producer = Task {
            for i in 1 ... 5 { try await handoff.send(i) }
            handoff.finish()
        }
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
        let producer = Task {
            for i in 1 ... 10 { try await handoff.send(i) }
            handoff.finish()
        }
        await settle()
        #expect(handoff.sentCount == 1)

        #expect(try await handoff.next() == 1)
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

    @Test("finish fires onTermination with its error, and a later cancel does not fire again")
    func finishThenCancelFiresOnce() async throws {
        let probe = TerminationProbe()
        let handoff = ResponseHandoff<Int>(onTermination: { probe.record($0) })
        handoff.finish(throwing: Boom())
        handoff.cancel()
        #expect(probe.count == 1)
        #expect(probe.last == "\(Boom())")
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
        let producer = Task {
            for i in 1 ... 100 { try await handoff.send(i) }
            handoff.finish()
        }
        func consumeFirst() async throws -> Int? {
            for try await value in handoff.makeStream() { return value }
            return nil
        }
        #expect(try await consumeFirst() == 1)
        await #expect(throws: CancellationError.self) { try await producer.value }
        #expect(probe.count == 1)
    }

    @Test("Cancelling the consumer task cancels the hand-off")
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
        _ = await consumer.result
        #expect(probe.count == 1)
        await #expect(throws: CancellationError.self) { try await handoff.send(1) }
    }

    @Test("makeStream(_:) skips elements the transform maps to nil")
    func transformSkips() async throws {
        let handoff = ResponseHandoff<Int>(capacity: 4)
        for i in 1 ... 4 { try await handoff.send(i) }
        handoff.finish()
        let evens = handoff.makeStream { $0 % 2 == 0 ? $0 : nil }
        var received: [Int] = []
        for try await value in evens { received.append(value) }
        #expect(received == [2, 4])
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ResponseHandoffTests`
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
                    if state.terminal != nil {
                        return .fail
                    }
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
                case .fail:
                    continuation.resume(throwing: CancellationError())
                case let .resumeConsumer(consumer):
                    consumer.resume(returning: element)
                    continuation.resume()
                case .done:
                    continuation.resume()
                case .suspend:
                    break
                }
            }
        } onCancel: {
            cancel()
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
                        // An AsyncSequence ends after throwing once.
                        state.terminal = .finished(nil)
                        return .fail(error)
                    case .finished(nil)?, .cancelled?:
                        return .end
                    case nil:
                        state.consumer = continuation
                        return .suspend
                    }
                }
                switch action {
                case let .deliver(element, wake):
                    wake?.resume()
                    continuation.resume(returning: element)
                case let .fail(error):
                    continuation.resume(throwing: error)
                case .end:
                    continuation.resume(returning: nil)
                case .suspend:
                    break
                }
            }
        } onCancel: {
            cancel()
        }
    }

    package func finish(throwing error: (any Error)? = nil) {
        let (first, consumer): (Bool, CheckedContinuation<Element?, any Error>?) = state.withLock { state in
            guard state.terminal == nil else { return (false, nil) }
            let consumer = state.consumer
            state.consumer = nil
            // A waiting consumer means the buffer is empty: hand it the outcome directly.
            state.terminal = (consumer != nil && error != nil) ? .finished(nil) : .finished(error)
            return (true, consumer)
        }
        guard first else { return }
        if let consumer {
            if let error {
                consumer.resume(throwing: error)
            } else {
                consumer.resume(returning: nil)
            }
        }
        onTermination(error)
    }

    package func cancel() {
        let (first, consumer, producer): (Bool, CheckedContinuation<Element?, any Error>?, CheckedContinuation<Void, any Error>?) = state.withLock { state in
            guard state.terminal == nil else { return (false, nil, nil) }
            state.terminal = .cancelled
            state.buffer.removeAll()
            let consumer = state.consumer
            let producer = state.producer?.continuation
            state.consumer = nil
            state.producer = nil
            return (true, consumer, producer)
        }
        guard first else { return }
        consumer?.resume(returning: nil)
        producer?.resume(throwing: CancellationError())
        onTermination(nil)
    }

    /// Wraps the hand-off as a pull-based stream. Call at most once per hand-off.
    ///
    /// The stream's closure holds a sentinel that cancels the hand-off when the stream is
    /// released — after `break` once it leaves scope, when dropped un-iterated, or when the
    /// consuming task is cancelled.
    package func makeStream<T: Sendable>(_ transform: @escaping @Sendable (Element) throws -> T?) -> AsyncThrowingStream<T, any Error> {
        let sentinel = CancelOnDeinit(self)
        return AsyncThrowingStream(unfolding: {
            while let element = try await sentinel.handoff.next() {
                if let value = try transform(element) {
                    return value
                }
            }
            return nil
        })
    }

    package func makeStream() -> AsyncThrowingStream<Element, any Error> {
        makeStream { $0 }
    }
}

/// Cancels its hand-off when the stream that captured it is released.
private final class CancelOnDeinit<Element: Sendable>: Sendable {
    let handoff: ResponseHandoff<Element>

    init(_ handoff: ResponseHandoff<Element>) {
        self.handoff = handoff
    }

    deinit {
        handoff.cancel()
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter ResponseHandoffTests`
Expected: all 9 tests PASS. Run it 5 times (`for i in 1 2 3 4 5; do swift test --filter ResponseHandoffTests || break; done`) to catch scheduling flakiness.

- [ ] **Step 5: Commit**

```bash
git add Sources/KurrentDB/Core/ResponseHandoff.swift Tests/MockClientTests/ResponseHandoffTests.swift
git commit -m "[ADD] ResponseHandoff: bounded single-producer hand-off with cancel-on-release stream"
```

---

### Task 3: Scoped execution path (`performScoped`)

**Files:**
- Modify: `Sources/GRPCEncapsulates/ResponseHandlable.swift` (append after `BufferedStreamResponse`)
- Create: `Sources/KurrentDB/Core/Additions/Usecase/UnaryStream+Scoped.swift`
- Modify: `Sources/KurrentDB/Streams/Usecase/Specified/Streams.Read.swift:12` and its struct body
- Modify: `Sources/KurrentDB/Streams/Usecase/All/Streams.ReadAll.swift:13` and its struct body
- Test: `Tests/MockClientTests/ScopedReadPathTests.swift`

**Interfaces:**
- Consumes: `ResponseHandoff` (Task 2); `withRetry(policy:selectNode:invalidate:operation:)` (`Core/RetryPolicy.swift:128`); `withRethrowingError(usage:action:)` (`Core/Error/KurrentError.swift:198,212`); `Metadata(from:overriding:)`; `ConnectionProvider.acquire(_:)`.
- Produces:
  - `package protocol ScopedStreamResponse: UnaryStream, BufferedStreamResponse` with `func call<Result: Sendable>(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, onResponse: @Sendable @escaping (StreamingClientResponse<UnderlyingResponse>) async throws -> Result) async throws -> Result`
  - `package final class ScopedCall<Response: Sendable>: Sendable` with `let handoff: ResponseHandoff<Response>` and `func close() async`
  - `extension ScopedStreamResponse where Transport == HTTP2ClientTransport.Posix`:
    - `func open(node: Node, callOptions: CallOptions, credentials: Authentication?) async throws(KurrentError) -> ScopedCall<Response>`
    - `func performScoped<R>(selector: NodeSelector, callOptions: CallOptions, credentials: Authentication? = nil, isolation: isolated (any Actor)? = #isolation, body: (AsyncThrowingStream<Response, any Error>) async throws -> R) async throws -> R`

- [ ] **Step 1: Write the failing tests**

```swift
//
//  ScopedReadPathTests.swift
//  swift-kurrentdb
//
//  No server needed: everything points at 127.0.0.1:1 (ECONNREFUSED). Verifies that the scoped
//  path uses the shared connection, fails before calling body, and returns the lease.
//

import GRPCCore
import Synchronization
import Testing
@testable import KurrentDB

/// Counts body invocations; a class so closures can capture it.
private final class CallCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }
    func hit() { count.withLock { $0 += 1 } }
}

@Suite("Scoped read path", .serialized, .timeLimit(.minutes(1)))
struct ScopedReadPathTests {
    private static let refused = Endpoint(host: "127.0.0.1", port: 1)

    private func makeInfo(supporting descriptors: [GRPCCore.MethodDescriptor]) -> ServerFeatures.ServiceInfo {
        ServerFeatures.ServiceInfo(
            serverVersion: "test",
            supportedMethods: descriptors.map {
                ServerFeatures.SupportedMethod(methodName: $0.method, serviceName: $0.service.fullyQualifiedService, features: [])
            }
        )
    }

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

    private var boundedCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(2)
        return options
    }

    @Test("Read: a refused connection throws KurrentError before body runs, on the shared path, lease returned")
    func readFailsBeforeBody() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let selector = await makeSelector(supporting: [usecase.methodDescriptor])
        defer { selector.connections.shutdown() }
        let bodyCalls = CallCounter()

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.performScoped(selector: selector, callOptions: boundedCallOptions) { _ in
                bodyCalls.hit()
            }
        }

        #expect(bodyCalls.value == 0)
        #expect(selector.connections.createdSharedConnectionCount == 1)
        #expect(selector.connections.createdDedicatedConnectionCount == 0)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("ReadAll: same guarantees")
    func readAllFailsBeforeBody() async throws {
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: .init())
        let selector = await makeSelector(supporting: [usecase.methodDescriptor])
        defer { selector.connections.shutdown() }
        let bodyCalls = CallCounter()

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.performScoped(selector: selector, callOptions: boundedCallOptions) { _ in
                bodyCalls.hit()
            }
        }

        #expect(bodyCalls.value == 0)
        #expect(selector.connections.createdSharedConnectionCount == 1)
        #expect(selector.connections.sharedEntrySnapshot(for: Self.refused)?.retainCount == 0)
    }

    @Test("Unsupported method throws unsupportedFeature without acquiring a lease")
    func unsupportedFeature() async throws {
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: "any"), options: .init())
        let selector = await makeSelector(supporting: [])
        defer { selector.connections.shutdown() }

        await #expect(throws: KurrentError.self) {
            _ = try await usecase.performScoped(selector: selector, callOptions: boundedCallOptions) { _ in }
        }
        #expect(selector.connections.createdSharedConnectionCount == 0)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift test --filter ScopedReadPathTests`
Expected: FAIL to compile — `value of type 'Streams<SpecifiedStream>.Read' has no member 'performScoped'`.

- [ ] **Step 3: Add the protocol** — append to `Sources/GRPCEncapsulates/ResponseHandlable.swift`:

```swift
/// A buffered stream usecase that can also hand its server-streaming call to a caller-owned
/// handler, for KurrentDB's scoped delivery (`streams(...).delivery(.scoped).read`).
///
/// `call` must invoke this usecase's generated client method and pass `onResponse` through
/// unchanged; the scoped driver owns iteration, backpressure and the RPC's lifetime.
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

In `Streams.Read.swift`, change the declaration line to:

```swift
    public struct Read: UnaryStream, BufferedStreamResponse, ScopedStreamResponse {
```

and add inside the struct, after `send(...)`:

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

Do the same in `Streams.ReadAll.swift` (declaration `public struct ReadAll: UnaryStream, BufferedStreamResponse, ScopedStreamResponse {`, identical `call` body).

- [ ] **Step 5: Implement the driver** — create `Sources/KurrentDB/Core/Additions/Usecase/UnaryStream+Scoped.swift`:

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

    func open() {
        resolve(.success(()))
    }

    func fail(_ error: any Error) {
        resolve(.failure(error))
    }

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
                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            fail(CancellationError())
        }
    }
}

/// An accepted scoped RPC: the task running it, its hand-off and its shared-connection lease.
package final class ScopedCall<Response: Sendable>: Sendable {
    package let handoff: ResponseHandoff<Response>
    private let lease: SharedLease
    private let task: Task<Void, Never>

    fileprivate init(handoff: ResponseHandoff<Response>, lease: SharedLease, task: Task<Void, Never>) {
        self.handoff = handoff
        self.lease = lease
        self.task = task
    }

    /// Ends the RPC and returns the lease. Returns only after the RPC task has finished, so
    /// nothing of this call outlives it. Cancelling the task cancels only this RPC; the shared
    /// connection stays up for other calls.
    package func close() async {
        handoff.cancel()
        task.cancel()
        await task.value
        lease.release()
    }
}

/// Scoped delivery: the RPC lives exactly as long as the caller's `body`.
extension ScopedStreamResponse where Transport == HTTP2ClientTransport.Posix {
    package func performScoped<R>(
        selector: NodeSelector,
        callOptions: CallOptions,
        credentials: Authentication? = nil,
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<Response, any Error>) async throws -> R
    ) async throws -> R {
        // Retry covers only establishing the call: once body has seen events, a retry would
        // hand them to it a second time.
        let call = try await withRetry(
            policy: selector.retryPolicy,
            selectNode: { try await selector.select() },
            invalidate: { await selector.invalidate() }
        ) { node in
            try await open(node: node, callOptions: callOptions, credentials: credentials)
        }

        let result: R
        do {
            result = try await body(call.handoff.makeStream())
        } catch {
            await call.close()
            throw error
        }
        await call.close()
        return result
    }

    /// Starts the RPC on the shared connection and returns once the server accepted it.
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
            throw error
        }
        return call
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter "ScopedReadPathTests|UnaryStreamConnectionPathTests|ResponseHandoffTests"`
Expected: all PASS (the existing `UnaryStreamConnectionPathTests` proves `read()` still takes the buffered shared path).

- [ ] **Step 7: Commit**

```bash
git add Sources/GRPCEncapsulates/ResponseHandlable.swift Sources/KurrentDB/Core/Additions/Usecase/UnaryStream+Scoped.swift Sources/KurrentDB/Streams/Usecase/Specified/Streams.Read.swift Sources/KurrentDB/Streams/Usecase/All/Streams.ReadAll.swift Tests/MockClientTests/ScopedReadPathTests.swift
git commit -m "[ADD] scoped execution path for Read/ReadAll on the shared connection"
```

---

### Task 4: Public API — `delivery(.scoped).read`

**Files:**
- Create: `Sources/KurrentDB/Core/ResponseDelivery.swift`
- Create: `Sources/KurrentDB/Streams/API/Streams+ScopedDelivery.swift`
- Modify: `Tests/StreamsTests/ScopedReadLiveTests.swift` (add tests)

**Interfaces:**
- Consumes: `performScoped(selector:callOptions:credentials:isolation:body:)` and `open(node:callOptions:credentials:)` (Task 3); `Streams.selector`, `.callOptions`, `.overrideCredentials`, `.identifier` (internal / public members of `Streams`).
- Produces:
  - `public protocol ResponseDelivery: Sendable`
  - `public struct ScopedDelivery: ResponseDelivery` + `static var scoped: ScopedDelivery`
  - `Streams.delivery(_ delivery: ScopedDelivery) -> ScopedStreams<Target>`
  - `public struct ScopedStreams<Target: StreamsTarget>: Sendable`
  - `ScopedStreams.read(configure:isolation:body:)` for `Target: SpecifiedStreamTarget` and `Target == AllStreamsTarget`

- [ ] **Step 1: Write the failing live tests** — add inside `ScopedReadLiveTests`:

```swift
    private struct BodyError: Error, Equatable {}

    private func sharedRetainCount(_ client: KurrentDBClient) async throws -> Int? {
        let node = try await client.selector.select()
        return client.selector.connections.sharedEntrySnapshot(for: node.endpoint)?.retainCount
    }

    @Test("Scoped read returns the same events as read()")
    func scopedMatchesBuffered() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 50, to: stream)

        let buffered = try await stream.read().reduce(into: [UUID]()) { ids, response in
            ids.append(try response.event.record.id)
        }
        let scoped = try await stream.delivery(.scoped).read { events in
            try await events.reduce(into: [UUID]()) { ids, response in
                ids.append(try response.event.record.id)
            }
        }
        #expect(scoped == buffered)
        #expect(scoped.count == 50)
    }

    @Test("Breaking after the first event returns the lease, and production stays bounded")
    func earlyBreakReleasesLease() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let name = "ScopedRead-\(UUID().uuidString)"
        let stream = client.streams(specified: name)
        try await appendEvents(count: 300, to: stream)

        let first = try await stream.delivery(.scoped).read { events in
            for try await response in events { return try response.event.record.id }
            return nil
        }
        #expect(first != nil)
        #expect(try await sharedRetainCount(client) == 0)

        // Bounded production, observed on the internal call.
        let node = try await client.selector.select()
        let usecase = Streams<SpecifiedStream>.Read(from: .init(name: name), options: .init())
        let call = try await usecase.open(node: node, callOptions: .defaults, credentials: nil)
        _ = try await call.handoff.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(call.handoff.sentCount - call.handoff.deliveredCount <= call.handoff.capacity)
        #expect(call.handoff.sentCount < 300)
        await call.close()
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("An error thrown by body reaches the caller unchanged and the lease is returned")
    func bodyErrorPropagates() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 10, to: stream)

        await #expect(throws: BodyError.self) {
            try await stream.delivery(.scoped).read { events in
                for try await _ in events { throw BodyError() }
            }
        }
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("Cancelling the caller's task while body iterates ends the read and returns the lease")
    func callerCancellation() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 300, to: stream)

        let reader = Task {
            try await stream.delivery(.scoped).read { events in
                for try await _ in events {
                    try await Task.sleep(for: .milliseconds(50))
                }
            }
        }
        try await Task.sleep(for: .milliseconds(200))
        reader.cancel()
        _ = await reader.result
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("A stream that escapes body ends immediately when iterated later")
    func escapedStreamEnds() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-\(UUID().uuidString)")
        try await appendEvents(count: 20, to: stream)

        let escaped = try await stream.delivery(.scoped).read { events in events }
        var count = 0
        for try await _ in escaped { count += 1 }
        #expect(count == 0)
        #expect(try await sharedRetainCount(client) == 0)
    }

    @Test("Reading a missing stream fails the same way as read()")
    func missingStream() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "ScopedRead-missing-\(UUID().uuidString)")

        var bufferedError: (any Error)?
        do { for try await _ in try await stream.read() {} } catch { bufferedError = error }
        var scopedError: (any Error)?
        do { try await stream.delivery(.scoped).read { events in for try await _ in events {} } } catch { scopedError = error }

        #expect(bufferedError != nil)
        #expect(scopedError.map { "\($0)" } == bufferedError.map { "\($0)" })
    }

    @Test("$all scoped read with a limit stops after the limit")
    func allStreamsScoped() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let count = try await client.allStreams.delivery(.scoped).read {
            $0.limit = 5
        } body: { events in
            try await events.reduce(0) { total, _ in total + 1 }
        }
        #expect(count == 5)
        #expect(try await sharedRetainCount(client) == 0)
    }
```

- [ ] **Step 2: Run to verify failure**

Run: `swift build --build-tests`
Expected: FAIL — `value of type 'Streams<SpecifiedStream>' has no member 'delivery'`.

- [ ] **Step 3: Implement `ResponseDelivery`** — `Sources/KurrentDB/Core/ResponseDelivery.swift`:

```swift
//
//  ResponseDelivery.swift
//  KurrentCore
//

/// How a streaming response is delivered to the caller.
///
/// Without a delivery, `read()` returns a stream the SDK has already filled: the RPC is over
/// when `read()` returns, and memory grows with the result. ``ScopedDelivery`` hands the
/// events to a closure as they arrive, with backpressure, and ends the RPC when the closure
/// returns.
public protocol ResponseDelivery: Sendable {}

/// Delivers events to a closure; the RPC lives exactly as long as that closure.
public struct ScopedDelivery: ResponseDelivery {
    public init() {}
}

extension ResponseDelivery where Self == ScopedDelivery {
    /// Events are delivered to a closure with backpressure; the RPC ends when the closure returns.
    public static var scoped: ScopedDelivery { .init() }
}
```

- [ ] **Step 4: Implement `ScopedStreams`** — `Sources/KurrentDB/Streams/API/Streams+ScopedDelivery.swift`:

````swift
//
//  Streams+ScopedDelivery.swift
//  KurrentStreams
//

extension Streams {
    /// Returns an interface whose reads deliver events to a closure with backpressure.
    ///
    /// ```swift
    /// let total = try await client.streams(specified: "orders")
    ///     .delivery(.scoped)
    ///     .read { events in
    ///         try await events.reduce(0) { count, _ in count + 1 }
    ///     }
    /// ```
    ///
    /// - Parameter delivery: ``ScopedDelivery/scoped``.
    /// - Returns: A ``ScopedStreams`` bound to the same target, credentials and call options.
    public func delivery(_ delivery: ScopedDelivery) -> ScopedStreams<Target> {
        ScopedStreams(base: self)
    }
}

/// Stream reads with scoped delivery: memory stays bounded while events are consumed, and
/// when `body` returns or throws the RPC has ended and its connection lease is returned.
///
/// Only `read` is scoped; use the `Streams` instance for every other operation.
public struct ScopedStreams<Target: StreamsTarget>: Sendable {
    let base: Streams<Target>
}

extension ScopedStreams where Target: SpecifiedStreamTarget {
    /// Reads events from the stream and hands them to `body` as they arrive.
    ///
    /// ```swift
    /// try await client.streams(specified: "orders")
    ///     .delivery(.scoped)
    ///     .read {
    ///         $0.limit = 100
    ///     } body: { events in
    ///         for try await response in events {
    ///             print(try response.event.record.eventType)
    ///         }
    ///     }
    /// ```
    ///
    /// The stream is valid only inside `body`; iterated after `read` returned, it ends at once.
    /// Errors thrown by `body` are rethrown unchanged. Failures before `body` is called are
    /// retried according to the client's retry policy and surface as `KurrentError`.
    ///
    /// - Parameters:
    ///   - configure: Configures ``Streams/Read/Options`` (direction, limit, starting revision).
    ///   - body: Consumes the events. Its return value is returned by `read`.
    public func read<R>(
        configure: @Sendable (inout Streams<Target>.Read.Options) -> Void = { _ in },
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<Streams<Target>.Read.Response, any Error>) async throws -> R
    ) async throws -> R {
        var options = Streams<Target>.Read.Options()
        configure(&options)
        let usecase = Streams<Target>.Read(from: base.identifier, options: options)
        return try await usecase.performScoped(
            selector: base.selector,
            callOptions: base.callOptions,
            credentials: base.overrideCredentials,
            body: body
        )
    }
}

extension ScopedStreams where Target == AllStreamsTarget {
    /// Reads events from `$all` and hands them to `body` as they arrive.
    ///
    /// ```swift
    /// let count = try await client.allStreams
    ///     .delivery(.scoped)
    ///     .read {
    ///         $0.limit = 10
    ///     } body: { events in
    ///         try await events.reduce(0) { total, _ in total + 1 }
    ///     }
    /// ```
    ///
    /// The stream is valid only inside `body`; iterated after `read` returned, it ends at once.
    ///
    /// - Parameters:
    ///   - configure: Configures ``Streams/ReadAll/Options`` (position, direction, filter, limit).
    ///   - body: Consumes the events. Its return value is returned by `read`.
    public func read<R>(
        configure: @Sendable (inout Streams<AllStreamsTarget>.ReadAll.Options) -> Void = { _ in },
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<Streams<AllStreamsTarget>.ReadAll.Response, any Error>) async throws -> R
    ) async throws -> R {
        var options = Streams<AllStreamsTarget>.ReadAll.Options()
        configure(&options)
        let usecase = Streams<AllStreamsTarget>.ReadAll(options: options)
        return try await usecase.performScoped(
            selector: base.selector,
            callOptions: base.callOptions,
            credentials: base.overrideCredentials,
            body: body
        )
    }
}
````

If `Streams<Target>.Read(from:options:)` or `Streams<Target>.Read.Options` does not resolve for a generic `Target: SpecifiedStreamTarget`, check how `Streams+SpecifiedStreamTarget.swift:127-132` names them (it uses `Read`, `Read.Options` inside `extension Streams where Target: SpecifiedStreamTarget`) and match that spelling — e.g. move the body of `read` into a `package` helper on `Streams where Target: SpecifiedStreamTarget` and call it from `ScopedStreams`.

- [ ] **Step 5: Verify the single-trailing-closure form compiles** — the doc example `.read { events in ... }` (one trailing closure) must bind to `body`, not `configure`. It is covered by the `///` example above, compiled in Task 6; also run `swift build --build-tests` now and confirm `escapedStreamEnds` (which uses that form) compiles.

- [ ] **Step 6: Run the tests**

Run: `swift test --filter "ScopedReadLiveTests|ScopedReadPathTests"`
Expected: all PASS.

- [ ] **Step 7: Commit**

```bash
git add Sources/KurrentDB/Core/ResponseDelivery.swift Sources/KurrentDB/Streams/API/Streams+ScopedDelivery.swift Tests/StreamsTests/ScopedReadLiveTests.swift
git commit -m "[ADD] delivery(.scoped).read for specified streams and \$all"
```

---

### Task 5: Subscription backpressure

**Files:**
- Modify: `Sources/KurrentDB/Streams/Streams.Subscription.swift`
- Modify: `Sources/KurrentDB/Streams/Usecase/Specified/Streams.Subscribe.swift:50-75` (`send`) and `:205-243` (`Subscription.init(messages:)`)
- Modify: `Sources/KurrentDB/Streams/Usecase/All/Streams.SubscribeAll.swift:45-70` (`send`) and `:212-249` (`Subscription.init(messages:)`)
- Test: `Tests/StreamsTests/SubscriptionBackpressureLiveTests.swift`

**Interfaces:**
- Consumes: `ResponseHandoff` (Task 2).
- Produces: `Streams.Subscription` with `package let messages: ResponseHandoff<Streams<Target>.Read.UnderlyingResponse>` and `package init(events:subscriptionId:messages:)`; public `events`, `subscriptionId`, `cancel()` unchanged.

- [ ] **Step 1: Write the failing live tests**

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

    private func event() -> EventData {
        EventData(eventType: "Backpressure-Test", model: ["Description": "backpressure"])
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
        _ = try await stream.append(events: (0 ..< 300).map { _ in event() }) { $0.expectedRevision = .any }

        // Subscribe starts at the end by default.
        let subscription = try await stream.subscribe { $0.revision = .start }
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .milliseconds(500))

        #expect(subscription.messages.sentCount - subscription.messages.deliveredCount <= subscription.messages.capacity)
        #expect(subscription.messages.sentCount < 300)
        subscription.cancel()
    }

    @Test("cancel() while the consumer waits ends the loop and closes the dedicated connection")
    func cancelWhileWaiting() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let stream = client.streams(specified: "Backpressure-\(UUID().uuidString)")
        _ = try await stream.append(events: [event()]) { $0.expectedRevision = .any }

        let subscription = try await stream.subscribe { $0.revision = .start }
        let consumer = Task {
            var count = 0
            for try await _ in subscription.events { count += 1 }
            return count
        }
        try await Task.sleep(for: .milliseconds(300))
        #expect(client.selector.connections.activeDedicatedConnectionCount == 1)

        subscription.cancel()
        #expect(try await consumer.value == 1)
        #expect(try await eventually { client.selector.connections.activeDedicatedConnectionCount == 0 })
    }

    @Test("$all subscription keeps the buffer bounded too")
    func allStreamsSlowConsumer() async throws {
        let client = KurrentDBClient(settings: settings)
        defer { try? client.shutdown() }
        let subscription = try await client.allStreams.subscribe { $0.position = .start }
        var iterator = subscription.events.makeAsyncIterator()
        _ = try await iterator.next()
        try await Task.sleep(for: .milliseconds(500))
        #expect(subscription.messages.sentCount - subscription.messages.deliveredCount <= subscription.messages.capacity)
        subscription.cancel()
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `swift build --build-tests`
Expected: FAIL — `value of type 'Streams<SpecifiedStream>.Subscription' has no member 'messages'`.

- [ ] **Step 3: Rewrite `Streams.Subscription`** — replace the struct in `Sources/KurrentDB/Streams/Streams.Subscription.swift`:

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

- [ ] **Step 4: Rewrite `Subscribe.send` and its `Subscription.init(messages:)`** in `Streams.Subscribe.swift`:

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

- [ ] **Step 5: Same for `SubscribeAll`** in `Streams.SubscribeAll.swift` — `send` identical to Step 4 (it has the same body today); `Subscription.init(messages:)`:

```swift
extension Streams.Subscription where Target == AllStreamsTarget {
    package init(messages: ResponseHandoff<Streams.SubscribeAll.UnderlyingResponse>) async throws {
        let first: Streams.SubscribeAll.UnderlyingResponse?
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
                logger.debug("[Streams.SubscribeAll] Subscription caught up with the $all stream.")
                return nil
            case let content?:
                logger.debug("[Streams.SubscribeAll] Received non-event subscription message: \(content)")
                return nil
            case nil:
                return nil
            }
        }
        self.init(events: events, subscriptionId: confirmation.subscriptionID, messages: messages)
    }
}
```

`SubscribeAll.UnderlyingResponse` is `ReadAll.UnderlyingResponse`, the same generated `ReadResp` type as `Read.UnderlyingResponse`, so it fits `Subscription.messages`. If the compiler disagrees, spell the stored property's type as `UnderlyingClient.UnderlyingService.Method.Read.Output`.

- [ ] **Step 6: Run the new tests and every existing subscription test**

Run: `swift test --filter "SubscriptionBackpressureLiveTests|StreamsTests|AllStreamsTargetTests|ConnectionReuseLiveTests"`
Expected: all PASS. `ConnectionReuseLiveTests` covers the dedicated-connection lifecycle of subscriptions.

Also build the V1 module, which returns `Streams<…>.Subscription`: `swift build --target KurrentDB_V1` → succeeds.

- [ ] **Step 7: Commit**

```bash
git add Sources/KurrentDB/Streams/Streams.Subscription.swift Sources/KurrentDB/Streams/Usecase/Specified/Streams.Subscribe.swift Sources/KurrentDB/Streams/Usecase/All/Streams.SubscribeAll.swift Tests/StreamsTests/SubscriptionBackpressureLiveTests.swift
git commit -m "[UPDATE] bound subscription buffering with a backpressured hand-off"
```

---

### Task 6: Documentation

**Files:**
- Modify: `Sources/KurrentDB/KurrentDB.docc/Articles/Reading events.md` (new section before `## Architecture`, line 189)
- Modify: `CLAUDE.md` (section "Key Design Patterns", after "Options via `inout` Trailing Closures")

- [ ] **Step 1: Add the DocC section** — insert before `## Architecture` in `Reading events.md`:

````markdown
## Reading with scoped delivery

`read()` returns once the whole result has arrived: memory grows with the result, and the RPC
is already over when you iterate. For large reads, use scoped delivery. Events reach your
closure as they arrive, the server is paused while you are busy, and when the closure returns
or throws the RPC has ended and its connection is released.

```swift
let total = try await client.streams(specified: "orders")
    .delivery(.scoped)
    .read {
        $0.limit = 10_000
    } body: { events in
        var total = 0.0
        for try await response in events {
            let order = try response.event.record.decode(to: OrderPlaced.self)
            total += order?.total ?? 0
        }
        return total
    }
```

The same works on `$all`:

```swift
let count = try await client.allStreams
    .delivery(.scoped)
    .read { events in
        try await events.reduce(0) { total, _ in total + 1 }
    }
```

The `events` stream is valid only inside the closure. Errors your closure throws are rethrown
unchanged; failures before the closure runs follow the client's retry policy.
````

- [ ] **Step 2: Add the design rule to `CLAUDE.md`** — after the "Options via `inout` Trailing Closures" subsection:

```markdown
#### Type Axes vs Options
Only a setting that changes the API's shape — return type, available operations, or the
lifetime of the RPC — becomes a type-level axis (e.g. `streams(specified:).delivery(.scoped)`
returns `ScopedStreams`, whose `read` takes a `body` closure). Settings that only change a
value (`limit`, `direction`, `filter`, credentials) stay in the `inout` options closure.
One axis, one meaning; name the axis after its meaning (`delivery`, a future `version` for the
server protocol), never `mode`/`policy`. Every axis keeps a parameterless default path.
```

- [ ] **Step 3: Compile every documentation example**

Run: `scripts/check-doc-snippets.sh`
Expected: exit 0. Errors point at the Markdown or Swift line to fix.

- [ ] **Step 4: Commit**

```bash
git add "Sources/KurrentDB/KurrentDB.docc/Articles/Reading events.md" CLAUDE.md
git commit -m "[UPDATE] document scoped read delivery and the type-axis rule"
```

---

### Task 7: Full verification

- [ ] **Step 1: Offline suites**

Run: `swift test --filter "MockClientTests|KurrentCoreTests"`
Expected: all PASS.

- [ ] **Step 2: Live suites** (cluster running)

Run: `swift test -v --no-parallel --disable-xctest --enable-swift-testing`
Expected: all PASS except suites that need extra infrastructure (`X509Tests` without a license, `KurrentDBPoolTests` without independent instances) — record which were skipped.

- [ ] **Step 3: Flakiness check on the new tests**

Run: `for i in 1 2 3 4 5; do swift test --filter "ResponseHandoffTests|ScopedReadLiveTests|SubscriptionBackpressureLiveTests" || break; done`
Expected: 5 clean runs.

- [ ] **Step 4: Record results** — append a "Review" section to this plan with the commands run, pass counts and anything skipped; commit:

```bash
git add docs/superpowers/plans/2026-10-04-scoped-read-delivery.md
git commit -m "[UPDATE] record verification results for scoped read delivery"
```

## Review

Date: 2026-10-04. Branch `feat/scoped-read-delivery`, 3-node TLS cluster (ports 2111-2113) healthy.

| Command | Result |
| --- | --- |
| `swift test --filter "MockClientTests\|KurrentCoreTests"` | PASS: 149 tests in 13 suites, 0 failures |
| `swift build --target KurrentDB_V1` | PASS |
| `scripts/check-doc-snippets.sh` | PASS: 189 snippets generated and compiled |
| `swift test -v --no-parallel --disable-xctest --enable-swift-testing` | PASS (exit 0), 0 failures. Per-run counts: 3, 7, 79, 16, 20, 6, 3, 65, 11, 149, 3, 1 tests |
| 5x `swift test --filter "ResponseHandoffTests\|ScopedReadLiveTests\|SubscriptionBackpressureLiveTests"` | 5 clean runs; each run 12 live tests in 2 suites (Scoped read, Subscription backpressure) plus the ResponseHandoff suite, all passed |

Skipped suites in the full run (skipped by the suites themselves, not failures):
- `X509Tests`: needs a licensed node (KURRENTDB_LICENSE_KEY).
- `KurrentDBPoolLiveTests`: needs independent KurrentDB instances.
- `AppendRecordsTests` (DCB): gated on env `KURRENTDB_SUPPORTS_APPEND_RECORDS=true`, which is not set locally.

Classified failures: none. `StreamsTests/testSubscribeAllExcludeSystemEvents` (previously flaky on cross-writer races) passed in this full run.
