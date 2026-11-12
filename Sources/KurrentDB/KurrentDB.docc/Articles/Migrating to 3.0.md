# Migrating from 2.x to 3.0

Learn what changes when you move a 2.x program to 3.0: reads deliver events as you iterate, deprecated API is gone, subscriptions can deliver the server's notifications next to the events, and stream metadata is stored in the server's format.

## Overview

A 2.x program that compiles against 3.0 behaves differently only at the sites listed on this page. Each change below shows the 2.x code and the 3.0 code and says what to do. Anything not listed here keeps working as in 2.6.2 — see "What did not change" at the end.

## Before you start

Raise the requirement in your `Package.swift`:

<!-- snippet:skip -->
```swift
dependencies: [
    .package(url: "https://github.com/gradyzhuo/swift-kurrentdb.git", from: "3.0.0")
]
```

Then check five things before you build.

<!-- S17 -->
- **Packages that pin swift-kurrentdb.** If a package you depend on pins swift-kurrentdb (swift-ddd-kit does), update it first or your resolution keeps 2.x.
- **Dependency floors.** 3.0 requires swift-protobuf 1.37.0 or later and grpc-swift-2 2.3.0 or later. If your package, or one you depend on, caps either below those versions (`exact:`, `.upToNextMinor(from:)` or a range that ends below them), resolution fails: lift the cap, or update that package or ask its maintainer to.
- **On 2.6.1 or earlier.** Upgrade to 2.6.2 first and run your tests there. 2.6.1 and 2.6.2 changed four behaviours that 3.0 keeps, all listed under 2.6 in What's new: a record's custom metadata reaches the server (and metadata that is not a JSON object now throws), `multiStreams.append` checks each event's expected revision, a subscription to a tombstoned stream ends with `resourceDeleted`, and `setMetadata` writes stream metadata the server applies, so metadata an earlier 2.x wrote with `maxAge`, `cacheControl`, `.userStream` or `.systemStream` has to be written again. This page compares 3.0 with 2.6.2.
- **`KurrentDB_V1`.** 3.0 has no `KurrentDB_V1` module. If you still `import KurrentDB_V1`, migrate on 2.6 first: pin `from: "2.6.2"`, follow [the 2.6 migration guide](https://gradyzhuo.github.io/swift-kurrentdb/2.6/documentation/kurrentdb/migration-guide), then delete the import and come back here. Before you delete it, sort every `client.shutdown()`: with `KurrentDB_V1` imported it shuts the **server** down, and once the import is gone the same line closes only the client, still compiling. Rewrite each one that means the server as `try await client.operations(of: .system).shutdown()`; leave each one that means the client as it is until the import is gone. The box at the top of <doc:Migration-guide> lists the uses no warning points at, such as a protocol of yours that requires `func shutdown() async throws`.
- **Stream metadata written by 2.6.1 or earlier.** Up to 2.6.1, `maxAge`, `cacheControl` and the two built-in ACLs were stored in a form the server ignores, together with the rest of that stream's metadata, and 3.0's `getMetadata()` throws for it; 2.6.2 stores them as the server reads them. Rewriting such metadata enforces `$maxCount`, `$tb` and `$acl` for the first time, and a 2.x client that writes metadata drops the top-level custom keys 3.0 writes. Read "Metadata is stored in the server's format" below before you write any stream's metadata.

## read() is lazy

In 2.x, `try await s.read()` fetched the whole result before it returned. In 3.0, `read()` is synchronous and does not throw: it returns a ``Streams/ReadCall`` and opens nothing. The RPC opens at the first element, errors are thrown from the loop, and the RPC stays open until the loop ends. <doc:Reading-events> explains how that keeps memory bounded.

Most 2.x read code still compiles. The table lists what the compiler says about each shape; the subsections after it cover what it does not say.

| 2.x code | 3.0 | Diagnostic |
|----------|-----|------------|
| `for try await r in try await s.read()` | lazy; the RPC is open during the loop | 2 warnings: "no 'async' operations occur within 'await' expression", "no calls to throwing functions occur within 'try' expression" |
| `let rs = try await s.read(); … for try await r in rs` | lazy; each `for` re-opens the RPC | the same 2 warnings |
| `try await s.read().reduce(…)` and the other shapes under "reduce, first and friends now stream" | lazy | **none** |
| `#expect(throws:) { try await s.read() }` | never throws, so the expectation fails | the same 2 warnings, inside the macro expansion |
| `do { rs = try await s.read() } catch { … }` | never throws | the same 2 warnings; "'catch' block is unreachable because no errors are thrown in 'do' block" only if nothing else in the block throws |
| A property, return type or parameter typed `AsyncThrowingStream<…ReadResponse, Error>` receiving `try await s.read()` | compile error; fix: `.buffered` | error: "cannot assign value of type 'Streams<SpecifiedStream>.ReadCall' to type 'AsyncThrowingStream<Streams<SpecifiedStream>.ReadResponse, any Error>'" |
| `s.read().lazy` | works | "'lazy' is deprecated: read() is lazy in 3.0; drop .lazy. Removed in 4.0." |
| `try client.shutdown()` | works; `shutdown()` no longer throws, because the client no longer stops an event-loop group | "no calls to throwing functions occur within 'try' expression"; fix: drop the `try` (for a `try await client.shutdown()` that came from `KurrentDB_V1` code, see Before you start) |
| `try await s.read().buffered` | unchanged | none |
| `let call: Streams<SpecifiedStream>.ReadCall = s.read()` | the annotation is no longer needed | none |
| `var it = rs.makeAsyncIterator()` | the iterator is a class | "variable 'it' was never mutated; consider changing to 'let' constant"; use `let` |

New in 3.0: inside an actor, a stored iterator is advanced with `it.next(isolation: self)`; 2.x's lazy iterator could not be (see Reads from an actor below).

### The try await moves to the loop
<!-- S8 -->

`read()` no longer has anything to wait for or throw. A loop over `try await s.read()` still compiles, with the two warnings above, and reads lazily. Drop both markers; the loop's own `try await` stays.

<!-- snippet:skip -->
```swift
for try await response in try await orders.read() { _ = response }
let responses = try await orders.read()
```

```swift
for try await response in orders.read() { _ = response }
let responses = orders.read()
```

### reduce, first and friends now stream
<!-- S1 -->

When `read()` is the operand of another `try await` — `reduce`, `first(where:)`, `contains`, `min`, `max`, `allSatisfy`, `prefix(…)` followed by a fold, your own `try await f(s.read())`, or `async let r = s.read()` — the outer call uses up the `try` and the `await`, and the compiler says nothing. The text is the same in both versions and is the right 3.0 code. What changes is when things happen: the RPC stays open while the operation runs, and the deadline, retry and error rules below apply. Add `.buffered` where you need the whole result first.

<!-- snippet:skip -->
```swift
let count = try await orders.read().reduce(0) { n, _ in n + 1 }   // 2.x: read() fetched everything first
```

```swift
let count = try await orders.read().reduce(0) { n, _ in n + 1 }   // 3.0: one RPC that ends when reduce does
let snapshot = try await orders.read().buffered                    // the whole result first, as in 2.x
```

### A stored read replays on every loop
<!-- S5 -->

A 2.x result was a snapshot: a second loop over it yielded nothing. A `ReadCall` describes a read: every loop opens a new RPC and reads from the start again, including events appended in between. Use `.buffered` where you relied on one fetch.

<!-- snippet:skip -->
```swift
let responses = try await orders.read()
for try await response in responses { _ = response }
for try await response in responses { _ = response }   // 2.x: nothing; the result was used up
```

```swift
let call = orders.read()
for try await response in call { _ = response }
for try await response in call { _ = response }   // a second RPC, from the start, with later appends
```

### A guard that no longer guards
<!-- S7 -->

`_ = try await s.read()`, or a `do`/`catch` around it, threw in 2.x when no node could be found. In 3.0 it opens nothing and never throws, so the code after it always runs; only the two warnings remain. A `#expect(throws:)` around `read()` now fails. To check that the read can be established, read one element: that throws what opening the read throws, including a missing stream, which 2.x reported only while you iterated. It cannot report a failure after the first event; iterate to the end, or use `.buffered`, when the caller must see every error the read can throw.

<!-- snippet:skip -->
```swift
_ = try await orders.read()   // 2.x: threw when no node could be found
```

```swift
for try await _ in orders.read().prefix(1) {}   // opens the RPC; throws what the read throws
```

### defaultDeadline bounds establishing the read
<!-- S2 -->

In 2.x, `defaultDeadline` bounded each attempt of a read, from after node selection to the end of the result. In 3.0 it bounds establishing a `read()` as one budget: node selection, every retry, the wait for a stream slot and for the server's first response. When it runs out, the first element throws `KurrentError.deadlineExceeded`, which is not retried. The iteration is not bounded. `.buffered` keeps the 2.x bound. A 2.6 `read().lazy` had no deadline at all: it now gets the establishment budget, so a node that is slow to select, or a wait for a stream slot, can throw `deadlineExceeded` where 2.6 waited. Raise `defaultDeadline`, or leave it at `.max`, if those reads must wait.

<!-- snippet:skip -->
```swift
let settings = ClientSettings.localhost().defaultDeadline(5_000)
let client = KurrentDBClient(settings: settings)
for try await response in try await client.streams(specified: "orders").read() {   // 2.x: 5 s per attempt, to the end
    _ = response
}
```

```swift
let settings = ClientSettings.localhost().defaultDeadline(5_000)
let client = KurrentDBClient(settings: settings)
for try await response in client.streams(specified: "orders").read() {   // 5 s to the first response; the loop is unbounded
    _ = response
}
let bounded = try await client.streams(specified: "orders").read().buffered   // 5 s per attempt, to the end
```

### CallOptions.timeout now spans the loop
<!-- S3 -->

A `CallOptions.timeout` is the gRPC call's deadline. In 2.x the call ended once the result was downloaded, so the timeout bounded the download. In 3.0 the call lasts as long as your loop, so the timeout includes the time the loop body takes. When it expires, the read ends at the next element with `KurrentError.deadlineExceeded` (see Errors a read throws below). For long loops, raise or drop the timeout, or read with `.buffered` and iterate the result afterwards.

<!-- snippet:skip -->
```swift
import GRPCCore

var options = CallOptions.defaults
options.timeout = .seconds(30)
let client = KurrentDBClient(settings: settings, defaultCallOptions: options)
for try await response in try await client.streams(specified: "orders").read() {
    _ = response
    try await Task.sleep(for: .milliseconds(10))   // 2.x: not counted; the 30 s covered the download
}
```

```swift
import GRPCCore

var options = CallOptions.defaults
options.timeout = .seconds(30)
let client = KurrentDBClient(settings: settings, defaultCallOptions: options)
for try await response in client.streams(specified: "orders").read() {
    _ = response
    try await Task.sleep(for: .milliseconds(10))   // counts against the 30 s
}
```

### Cancellation throws
<!-- S4 -->

In 2.x, `read()` returned only after it had fetched the whole result, so a loop whose task was cancelled still received every event and ended normally; only a task cancelled inside `read()` itself got `KurrentError.connectionClosed`. In 3.0 events arrive as you iterate, and after cancellation the next element throws `CancellationError`, which is not a `KurrentError`. A loop that used to finish with every event now stops partway through and throws. Catch `CancellationError` where a cancelled task must not count as a failed read, and never treat what such a loop saw as the whole result.

<!-- snippet:skip -->
```swift
let task = Task {
    for try await response in try await orders.read() { _ = response }   // 2.x: every event, then a normal end
}
task.cancel()
try await task.value
```

```swift
let task = Task {
    for try await response in orders.read() { _ = response }
}
task.cancel()
do {
    try await task.value
} catch is CancellationError {
    // the read was cut short
}
```

### Retries happen at the first element
<!-- S6 -->

2.x retried a read only when its deadline expired: an expired `defaultDeadline` or `CallOptions.timeout` was thrown from `read()` as `KurrentError.deadlineExceeded`, which reset the cached node and tried again. Every other failure of the selected node arrived while you iterated. 3.0 does the opposite: it retries a read until the server accepts it: a node failure — `notLeaderException`, `grpcConnectionError`, `grpcError` or `grpcRuntimeError` — resets the cached node, rediscovers and tries again under `ClientSettings.operationRetryPolicy`. An expired deadline before acceptance is final and keeps the node. Once the first element has arrived nothing is retried. When the attempts run out, the last error is thrown from the first element.

```swift
do {
    for try await response in orders.read() { _ = response }
} catch KurrentError.grpcConnectionError(let cause) {
    _ = cause   // the node refused the connection on every attempt, or became unavailable mid-read
}
```

### Give the client back with values, not reads
<!-- S10 -->

In 2.x, giving a borrowed client back shut nothing down: a client, facade or `Subscription` kept after `withBorrowedClient` returned went on working, and a read returned from the closure had already been fetched. In 3.0, giving back closes the borrowed client's connections, and everything kept past the closure ends with `KurrentError.connectionClosed`. The 2.x closure below now returns a `ReadCall` (with the two warnings) whose RPC opens after give-back and throws `connectionClosed`. Iterate inside the closure and return values. `withBorrowedClient` returns `nil` when no instance could be lent.

<!-- snippet:skip -->
```swift
let responses = try await withBorrowedClient { borrowed in
    try await borrowed.client.streams(specified: "orders").read()   // 2.x: fetched before give-back
}
```

```swift
let count = try await withBorrowedClient { borrowed in
    var n = 0
    for try await _ in borrowed.client.streams(specified: "orders").read() { n += 1 }
    return n
}   // Int?: nil when no instance could be lent
```

### A second connection per node
<!-- S11 -->

2.x opened one shared connection per node, plus a connection of its own for each subscription, persistent subscription and server-statistics call. 3.0 opens a second shared connection for `read()`, so a read still iterating never makes an append wait; `.buffered` reads and every other call stay on the first. Proxies and server connection limits see one more connection per node.

The server allows about 100 reads in progress per connection: the 101st waits inside its `defaultDeadline` budget, and reads nested 100 deep deadlock. The first `read()` to a node pays the connection setup, TLS included, inside its budget. <doc:Reading-events> has the details.

### Position frames are skipped
<!-- S12 -->

With `Read.Options.compatibility` at 1 or above, the server interleaves position frames with a stream read's events. 2.x failed every such read with `KurrentError.internalParsingError`. 3.0 skips the frames, as `$all` reads already did, and delivers the events.

<!-- snippet:skip -->
```swift
for try await response in try await orders.read(configure: { $0.compatibility = 1 }) {   // 2.x: internalParsingError
    _ = response
}
```

```swift
let call = orders.read { $0.compatibility = 1 }
for try await response in call { _ = response }   // events only
```

### Per-event cost
<!-- S13 -->

Off an actor, `read()` costs about what `.buffered` costs per event; from an actor, about 1.1×. `.buffered` is for snapshots, results iterated later and deadline-bounded reads, not for speed.

### shutdown() ends an open read
<!-- S14 -->

In 2.x a read went on after `shutdown()`, and an operation still discovering a node failed only after `maxDiscoveryAttempts`, with `KurrentError.serverError("Connection node not found.")`. In 3.0 `shutdown()` ends a read in progress with `KurrentError.connectionClosed` at its next element, also when the loop body calls it, and an operation in node discovery throws `connectionClosed` at once.

```swift
let reading = Task {
    for try await response in orders.read() { _ = response }
}
client.shutdown()
do {
    try await reading.value
} catch KurrentError.connectionClosed {
    // shutdown() ended the read
}
```

### Errors a read throws
<!-- S15 -->

In 2.x an error after the server had accepted a read or a catch-up subscription — the call cancelled, the node becoming unavailable — reached you as a raw `RPCError`. An expiring `CallOptions.timeout` did too on a `.lazy` read or a subscription; a 2.x `read()` threw it as a retried `KurrentError.deadlineExceeded` instead. In 3.0 a read throws exactly two types: `KurrentError` for everything the client or the server reports, and `CancellationError` when your task is cancelled. The gRPC status maps as for every other call: an expired timeout is `deadlineExceeded`, an unavailable node usually `grpcConnectionError(cause:)`, a cancelled call `connectionClosed`, and a status KurrentDB has no meaning for is `grpcError(cause:)`, with the `RPCError` as its cause.

`.buffered` and a subscription's `events` and `messages` map errors to `KurrentError` the same way, but they never throw `CancellationError`. A `.buffered` fetch cancelled midway throws `connectionClosed`, and a loop over a fetched `.buffered` result or over a subscription ends without throwing when its task is cancelled, so a `catch is CancellationError` around it never runs.

A `catch let error as RPCError` around a read or a catch-up subscription still compiles but never matches: the error falls through to the next clause or out of the function. Catch `KurrentError` instead. Persistent subscriptions are not affected (see "What did not change").

<!-- snippet:skip -->
```swift
do {
    for try await response in try await orders.read() { _ = response }
} catch let error as RPCError {
    _ = error   // 2.x: errors after the server accepted the read
}
```

```swift
do {
    for try await response in orders.read() { _ = response }
} catch let error as KurrentError {
    _ = error
} catch is CancellationError {
    // the task was cancelled
}
```

### When to write .buffered

Write `.buffered` where the 2.x behaviour was the point:

- a snapshot that later appends must not change;
- a read that `defaultDeadline` must bound to its end;
- a result you store and iterate later, after the code that fetched it has moved on;
- a property, parameter or return type typed `AsyncThrowingStream<…ReadResponse, any Error>`.

Everywhere else, drop the `try await` and iterate `read()`.

```swift
let all = try await orders.read { $0.limit = 1_000 }.buffered
```

### Reads from an actor

`for try await` over `read()` needs nothing new inside an actor: it passes the actor's isolation to the iterator. An iterator kept in actor state is advanced with `next(isolation: self)`. Call it from one task at a time, as with any async iterator: actor isolation does not serialize two calls across the `await`, and overlapping calls can open a second RPC that the iterator then loses track of.

<!-- snippet:toplevel -->
```swift
@MainActor final class OrdersViewModel {
    var rows: [String] = []

    func load() async throws {
        for try await response in orders.read() {   // nothing to add
            let eventType = try response.event.record.eventType
            rows.append(eventType)
        }
    }
}

actor Cursor {
    let iterator = orders.read().makeAsyncIterator()

    func next() async throws -> ReadEvent? {
        try await iterator.next(isolation: self)?.event
    }
}

func count<T: SpecifiedStreamTarget>(_ call: Streams<T>.ReadCall) async throws -> Int {
    try await call.reduce(0) { n, _ in n + 1 }
}
```

`ReadCall` belongs to its target: `client.streams(of: "orders")` is a `Streams<String>` and `client.streams(specified: "orders")` a `Streams<SpecifiedStream>`, so their reads have different types. A helper for reads of any named stream is generic, `where T: SpecifiedStreamTarget`, like `count` above.

### .lazy still compiles, with a warning

`read().lazy` returns the read itself and warns that it is deprecated; `ReadCall.Lazy` is a deprecated name for `ReadCall`. Both are removed in 4.0. Drop `.lazy`.

<!-- snippet:toplevel -->
```swift
@available(*, deprecated, message: "drop .lazy")
func legacy() async throws {
    for try await response in orders.read().lazy { _ = response }   // warning: 'lazy' is deprecated
}
```

## Removed and renamed API

Every declaration 2.x deprecated is gone. All rows but the last three carry a deprecation warning on 2.6, so a 2.6 build without deprecation warnings uses none of them. The `numberOfThreads:` rows and the `properties:` row were not deprecated: they fail to compile without a warning beforehand.

| Removed in 3.0 | Use instead | Note |
|----------------|-------------|------|
| `ClientSettings.certificate(path:)` | `certificate(path:fallback:)` | `fallback:` has no default value. `.none` keeps 2.6's refusal of an unreadable file, but throws `KurrentError.initializationError` when the settings are built (so it needs `try`), where 2.6 failed at the first connection; `.systemTrustRoots` leaves the file out, so the system's root certificates are trusted if no other CA is configured. |
| `cerificates` | `certificates` | |
| `cerificate(source:)` | `certificate(source:)` | |
| `cerificate(path:)` | `certificate(path:fallback:)` | As `certificate(path:)`. |
| `KurrentError.CurrentRevisionOption` | `KurrentError.CurrentRevisionState` | The same type, renamed. |
| `EventData(id:eventType:payload:customMetadata:)` with a value that is not a `Payload` | `EventData(eventType:model:customMetadata:)`, or `payload: .json(value)` | Keep `customMetadata:` as it is; for its own change see "Deprecated in 3.0" below. If the value was `Data` or `[UInt8]`, see "EventData with a Data payload" below. |
| `StreamFilter.onStreamName(prefix:)` | `onStreamName(prefixes:)` | |
| `SubscriptionFilter` | `StreamFilter` | The same type, renamed. |
| `KurrentDB_V1` (library and module) | the 2.x API | Migrate on 2.6 first (Before you start). |
| `client.shutdown()` from `KurrentDB_V1`, which shut the server down | `try await client.operations(of: .system).shutdown()` | Without the import the same line still compiles and closes the client instead: sort these on 2.6 (Before you start). |
| `KurrentDBClient(settings:numberOfThreads:defaultCallOptions:)` | `KurrentDBClient(settings:eventLoopGroup:defaultCallOptions:)` | See "eventLoopGroup replaces numberOfThreads" below. |
| `withBorrowedClient(numberOfThreads:maxAttempts:_:)` | `withBorrowedClient(eventLoopGroup:maxAttempts:_:)` | As above. |
| `EventRecord(id:data:schema:properties:)` | `EventRecord(id:data:schema:customMetadata:)` | It stored its properties without checking them. Without `properties:` the call compiles unchanged. See "Deprecated in 3.0" below. |

### EventData with a Data payload

The removed initialiser took any `Codable` value and stored it JSON-encoded. For `Data` that is a JSON string holding the bytes in base64, and for `[UInt8]` a JSON array of numbers. `payload: .json(value)` is the same encoding: write it to keep appending what the stream already holds. `data:` and `bytes:` store the bytes themselves, so they change the stored format; switch to them only once every reader of the stream expects the new one. Both default to `contentType: .json`: for bytes that are not JSON, pass `contentType: .binary`.

<!-- snippet:skip -->
```swift
let snapshot = EventData(eventType: "Snapshot", payload: someData)   // 2.x: stored "eyJvcmRlcklkIjoib3JkZXItMSJ9", a base64 JSON string
```

```swift
let same = EventData(eventType: "Snapshot", payload: .json(someData))               // the bytes 2.x stored
let raw = EventData(eventType: "Snapshot", data: someData)                          // the Data itself, labelled JSON on append
let blob = EventData(eventType: "Snapshot", data: someData, contentType: .binary)   // bytes that are not JSON
```

### eventLoopGroup replaces numberOfThreads
<!-- S16 -->

A 2.x client created a group of `numberOfThreads` threads, ran no connection on it — every connection ran on NIO's process-wide `.singletonMultiThreadedEventLoopGroup` — and stopped it in `shutdown()`. A 3.0 client runs every connection on the group you pass, by default that same singleton, so dropping the argument changes nothing at run time. A group you pass, such as your server's, now really carries the client's I/O. It must be a `MultiThreadedEventLoopGroup` or one of its event loops; a NIO Transport Services group crashes the process at the first connection. The client never shuts the group down: a group you create is yours to shut down. `client.shutdown()` only starts closing the connections, so stop the group once nothing else needs it, such as at process exit. `withBorrowedClient` takes the same parameter.

<!-- snippet:skip -->
```swift
let client = KurrentDBClient(settings: settings, numberOfThreads: 2)
```

```swift
import NIOPosix

let client = KurrentDBClient(settings: settings)                                    // the singleton group, which 2.x ran on
let shared = KurrentDBClient(settings: settings, eventLoopGroup: eventLoopGroup)    // a group your server already runs

let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
let isolated = KurrentDBClient(settings: settings, eventLoopGroup: group)          // threads of its own
isolated.shutdown()
try await group.shutdownGracefully()                                                // yours to stop, after the client
```

### shutdown() no longer throws

In 2.x, `shutdown()` threw what stopping the client's group threw. A 3.0 client owns no group, so `shutdown()` only closes its connections and throws nothing. `try client.shutdown()` compiles with the warning in the diagnostics table above, and a `do`/`catch` around it alone gets "'catch' block is unreachable because no errors are thrown in 'do' block": drop the `try` and the `do`/`catch`. A `try await client.shutdown()` from `KurrentDB_V1` code is the exception: on 2.6, decide whether it means the server or the client before you drop anything (Before you start).

<!-- snippet:skip -->
```swift
do {
    try client.shutdown()   // 2.x: threw when the event-loop group failed to stop
} catch {
    print("shutdown failed: \(error)")
}
```

```swift
client.shutdown()
```

## Subscription notifications

``Streams/Subscription/messages`` and its ``Streams/Subscription/Message`` enum are new in 3.0: they deliver the server's `caughtUp`, `fellBehind` and `checkpoint` notifications next to the events. A 2.x program does not use them, so nothing here breaks its build. <doc:Reading-events> shows the notifications and their payloads, and why a switch over `Message` ends with `@unknown default`, which a switch in your own package needs from Swift 6.2.3. If you built against `main` between PR #187 and the 3.0 release, the notification cases now carry payloads: `.checkpoint` binds a ``Streams/Subscription/Checkpoint``, not a ``StreamPosition``, so read its `position`. `"\(position)"` on the old binding still compiles, and now prints the whole `Checkpoint`.

### A tombstoned stream ends the subscription
<!-- S9 -->

Up to 2.6.0, when the stream a catch-up subscription followed was tombstoned, `events` delivered the server's `$streamDeleted` marker as an ordinary event, and the loop then threw a raw `RPCError`. Since 2.6.1, and in 3.0, `events` and `messages` deliver the events written before the tombstone, then throw `KurrentError.resourceDeleted(resource:)`, the error a read of a tombstoned stream throws; the marker is not delivered. A check for the stream's own `$streamDeleted` inside the loop never matches any more (one reached through a link still arrives): move what it did into a `catch`. Subscribing to a stream that is already tombstoned throws the same error from `subscribe`, as in 2.6. On `$all`, `$streamDeleted` is still delivered as a system event about the stream it names, and the subscription goes on. Code that already runs on 2.6.1 needs no change here.

<!-- snippet:skip -->
```swift
let subscription = try await orders.subscribe { $0.revision = .start }
for try await readEvent in subscription.events {
    if readEvent.record.eventType == "$streamDeleted" {
        break   // 2.6.0 and earlier: the tombstone arrived as an event, and a raw RPCError followed it
    }
}
```

```swift
do {
    let subscription = try await orders.subscribe { $0.revision = .start }
    for try await readEvent in subscription.events {
        _ = readEvent   // never the stream's own "$streamDeleted"
    }
} catch KurrentError.resourceDeleted(let stream) {
    print(stream, "was tombstoned")   // after any events written before the tombstone
}
```

## Stream metadata

### Metadata is stored in the server's format
<!-- S18 -->

Up to 2.6.1, ``StreamMetadata`` was encoded with Swift's synthesized `Codable`: `maxAge` and `cacheControl` became `Duration`'s `[high, low]` array, not seconds, and `.acl(.userStream)` and `.acl(.systemStream)` became the strings `"$userStreamAcl"` and `"$systemStreamAcl"`. 2.6.2 writes whole seconds, no `$acl` for `.userStream` and `$admins` for every permission for `.systemStream`. Every 2.x version nests custom properties under a `"customProperties"` key. 3.0 writes the object the server and other clients read: whole seconds, an `$acl` object or none, and custom keys at the top level. The same builder calls compile and store the new form, apart from the ACL cases and the deprecation below.

The server reads `$acl` only as an object of roles; `$userStreamAcl` and `$systemStreamAcl` are keys of the `$settings` stream that hold the defaults, not values of a stream's `$acl`. So 3.0 removes `.userStream` and `.systemStream`. Use ``StreamMetadata/Acl/serverDefault``, which removes `$acl` so the server applies the default from `$settings`, or ``StreamMetadata/Acl/stream(_:)`` with the stream's own roles. 2.x had no public initializer for ``StreamMetadata/StreamAcl``; 3.0 starts one from ``StreamMetadata/StreamAcl/defaults``, in which every permission falls back to `$settings`: `.acl(.stream(.defaults.writeRoles(["ops"])))`. Each permission is now a ``StreamMetadata/StreamAcl/Roles`` value, ``StreamMetadata/StreamAcl/Roles/defaults`` or ``StreamMetadata/StreamAcl/Roles/granted(_:)``: the role builders take it, so an array literal still compiles and a `[String]` variable is passed as `.granted(names)`, and the role properties return it, `.defaults` where 2.x returned `nil`. ``StreamMetadata``, ``StreamMetadata/StreamAcl`` and ``StreamMetadata/Acl`` are no longer `Codable`, since `JSONDecoder` and `JSONEncoder` do not read and write JSON as the server does; read stored metadata with ``StreamMetadata/init(data:)``. ``StreamMetadata/Acl`` has no `rawValue` either: ``StreamMetadata/Acl/serverDefault`` has no JSON form, since it is the absence of `$acl`, and the server ignores the whole metadata for `"$acl":null` as for a string. `acl(_:)` writes `$acl` as an object or removes it.

Metadata a 2.6.1 or earlier client wrote stays as it was until you write it again. If it set `maxAge`, `cacheControl` or one of the two ACL strings, the server accepted the write and then ignored the whole object: `$maxCount`, `$tb` and `$acl` in it were never enforced, so the stream kept every event and the default access rules applied to it. 3.0 reads metadata as strictly as the server and the .NET client do, so `getMetadata()` throws `KurrentError.internalParsingError` for such an object, naming the key, rather than report settings the server does not apply. Metadata 2.6.2 wrote, and metadata an earlier client wrote with custom properties only, reads, but `customProperties(as:)` sees the custom properties as one key named `customProperties`.

Write the metadata of those streams again from 3.0, as in the code below. Check each value before you write it: the rewrite enforces `$maxCount`, `$tb` and `$acl` for the first time. Events beyond `$maxCount`, or before `$tb`, become unreadable at once, and an `$acl` whose metadata write roles (`$mw`) leave out your own user stops you from changing the metadata again.

The other way round, a 2.6.1 or earlier client's `getMetadata()` throws on metadata that holds `$maxAge` or `$cacheControl` in seconds, whether 3.0, 2.6.2 or another client wrote it. Every 2.x client ignores top-level custom keys, and one that writes metadata drops 3.0's top-level custom keys; up to 2.6.1 it also stores the `[high, low]` form again. Upgrade every Swift client that reads or writes a stream's metadata before you write it from 3.0.

| 2.x code | 3.0 | Diagnostic |
|----------|-----|------------|
| `StreamMetadata().maxAge(…)`, `cacheControl(…)` | stores whole seconds; a sub-second part is truncated | none |
| `acl(.userStream)`, `acl(.systemStream)` | removed: up to 2.6.1 they wrote a string the server rejects, which made it ignore the whole metadata, and 2.6.2 writes no `$acl` and `$admins`. Use `acl(.serverDefault)` for the default, or `acl(.stream(…))` | "type 'StreamMetadata.Acl' has no member 'userStream'" |
| `StreamAcl` `readRoles(names)` … `metaWriteRoles(names)` with a `[String]` variable | pass `.granted(names)`; an array literal compiles as before, and `.defaults` removes the permission so the server applies the default from `$settings` | "cannot convert value of type '[String]' to expected argument type 'StreamMetadata.StreamAcl.Roles'" |
| `StreamAcl` `readRoles` … `metaWriteRoles` as `[String]?` | return ``StreamMetadata/StreamAcl/Roles``: `.defaults` for an absent permission, `.granted(roles)` otherwise | "initializer for conditional binding must have Optional type, not 'StreamMetadata.StreamAcl.Roles'"; `roles ?? []` still compiles, with a warning, and yields a `Roles` |
| `Acl.rawValue`, encoding or decoding an `Acl` | removed: `.serverDefault` is the absence of `$acl`, and `acl(_:)` writes `$acl` as an object or removes it. Print `String(reflecting: metadata)` to see the stored JSON | "value of type 'StreamMetadata.Acl' has no member 'rawValue'", "instance method 'encode' requires that 'StreamMetadata.Acl' conform to 'Encodable'" |
| `JSONEncoder().encode(metadata)`, `JSONDecoder().decode(StreamMetadata.self, from:)`, `record.decode(to: StreamMetadata.self)`, or a `StreamMetadata` or `StreamAcl` property in a `Codable` type of yours | removed: ``StreamMetadata`` and ``StreamMetadata/StreamAcl`` are no longer `Codable`, because `JSONDecoder` and `JSONEncoder` do not read and write JSON as the server reads it (see Metadata the server ignores in <doc:Stream-metadata>). Read stored metadata with ``StreamMetadata/init(data:)``, print `String(reflecting: metadata)` to see the JSON that is sent, and keep the field values, not the `StreamMetadata`, in a `Codable` type of your own | "instance method 'encode' requires that 'StreamMetadata' conform to 'Encodable'", "instance method 'decode(_:from:)' requires that 'StreamMetadata' conform to 'Decodable'", "type '…' does not conform to protocol 'Decodable'" |
| `customProperties(["tenant": "acme"])` | merges top-level keys into the object, where 2.x replaced the whole custom dictionary; a key starting with `$` is skipped and logged as a warning | "'customProperties' is deprecated: use customProperties(encoding:). Removed in 4.0." |
| `maxCount(…)`, `truncateBefore(…)`, `maxAge(…)`, `cacheControl(…)` | a value above the server's limit stops the program (see Limits in <doc:Stream-metadata>); `0` or a duration under one second is written and logged as a warning, and the server ignores that field | none |
| `getMetadata()` on metadata the server ignores | throws `KurrentError.internalParsingError` (see Metadata the server ignores in <doc:Stream-metadata>) | none |
| `metadata == other` | compares the whole object, `maxCount` included; an `$acl` role stored as `"ops"` equals one stored as `["ops"]`, as the server reads them, and role names are compared byte by byte, as the server matches them | none |
| `setMetadata(metadata:expectedRevision:)` with an `$acl` role name that reads as a date, such as `"2024-01-01T00:00:00"` | throws `KurrentError.encodingError` before anything is sent: the server would ignore the whole object (see Metadata the server ignores in <doc:Stream-metadata>) | none |

<!-- snippet:skip -->
```swift
let metadata = StreamMetadata()
    .maxAge(.seconds(60))
    .acl(.userStream)
    .customProperties(["tenant": "acme"])
try await orders.setMetadata(metadata: metadata)   // 2.6.1: {"$acl":"$userStreamAcl","$maxAge":[3,4659767778871345152],"customProperties":{"tenant":"acme"}}
                                                    // 2.6.2: {"$maxAge":60,"customProperties":{"tenant":"acme"}}
```

```swift
let metadata = try StreamMetadata()
    .maxAge(.seconds(60))
    .acl(.serverDefault)
    .customProperties(encoding: ["tenant": "acme"])
try await orders.setMetadata(metadata: metadata)   // {"$maxAge":60,"tenant":"acme"}
```

To rewrite what a 2.x client stored, decode the latest event of the `$$<stream>` metadata stream with a type that mirrors 2.x's encoding. Decoding `Duration` itself reads 2.6.1's `[high, low]` pair exactly, negative durations included, 2.6.2's whole seconds are read as they are, and `maxAge(_:)` and `cacheControl(_:)` store it in whole seconds:

<!-- snippet:toplevel -->
```swift
/// A stream's metadata as a 2.x Swift client stored it.
struct Legacy2xMetadata: Decodable {
    var maxCount: UInt64?
    var maxAge: Duration?                       // whole seconds (2.6.2) or Duration's [high, low]
    var truncateBefore: UInt64?
    var cacheControl: Duration?
    var acl: Acl?                               // nil for "$userStreamAcl" and "$systemStreamAcl"
    var customProperties: [String: String]?     // nested, not top-level keys

    /// The `$acl` object as 2.x stored it: each permission an array of role names. A single
    /// role name, as other tools may write it, is read as an array of one.
    struct Acl: Decodable {
        var read: [String]?
        var write: [String]?
        var delete: [String]?
        var metaRead: [String]?
        var metaWrite: [String]?

        enum CodingKeys: String, CodingKey {
            case read = "$r", write = "$w", delete = "$d", metaRead = "$mr", metaWrite = "$mw"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            func roles(_ key: CodingKeys) throws -> [String]? {
                if let role = try? container.decodeIfPresent(String.self, forKey: key) {
                    return [role]
                }
                return try container.decodeIfPresent([String].self, forKey: key)
            }
            read = try roles(.read)
            write = try roles(.write)
            delete = try roles(.delete)
            metaRead = try roles(.metaRead)
            metaWrite = try roles(.metaWrite)
        }

        var roles: StreamMetadata.StreamAcl {
            var roles = StreamMetadata.StreamAcl.defaults
            if let read { roles = roles.readRoles(.granted(read)) }
            if let write { roles = roles.writeRoles(.granted(write)) }
            if let delete { roles = roles.deleteRoles(.granted(delete)) }
            if let metaRead { roles = roles.metaReadRoles(.granted(metaRead)) }
            if let metaWrite { roles = roles.metaWriteRoles(.granted(metaWrite)) }
            return roles
        }
    }

    enum CodingKeys: String, CodingKey {
        case maxCount = "$maxCount", maxAge = "$maxAge", truncateBefore = "$tb"
        case cacheControl = "$cacheControl", acl = "$acl", customProperties
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        maxCount = try container.decodeIfPresent(UInt64.self, forKey: .maxCount)
        maxAge = try Self.duration(in: container, forKey: .maxAge)
        truncateBefore = try container.decodeIfPresent(UInt64.self, forKey: .truncateBefore)
        cacheControl = try Self.duration(in: container, forKey: .cacheControl)
        // A 2.x string ACL, "$userStreamAcl" or "$systemStreamAcl", is left out.
        let isStringAcl = (try? container.decodeIfPresent(String.self, forKey: .acl)) != nil
        acl = isStringAcl ? nil : try container.decodeIfPresent(Acl.self, forKey: .acl)
        customProperties = try container.decodeIfPresent([String: String].self, forKey: .customProperties)
    }

    /// Whole seconds, as 2.6.2 wrote them, or `Duration`'s `[high, low]`, as earlier versions did.
    static func duration(in container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Duration? {
        if let seconds = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return .seconds(seconds)
        }
        return try container.decodeIfPresent(Duration.self, forKey: key)
    }

    /// The same settings as 3.0 writes them; a 2.x string ACL becomes the server's default.
    func metadata() throws -> StreamMetadata {
        var metadata = StreamMetadata()
        if let maxCount { metadata = metadata.maxCount(maxCount) }
        if let maxAge { metadata = metadata.maxAge(maxAge) }
        if let truncateBefore { metadata = metadata.truncateBefore(truncateBefore) }
        if let cacheControl { metadata = metadata.cacheControl(cacheControl) }
        if let acl { metadata = metadata.acl(.stream(acl.roles)) }
        if let customProperties { metadata = try metadata.customProperties(encoding: customProperties) }
        return metadata
    }
}
```

A 2.x client replaced the whole object on every write, so the latest event holds only these keys. Rewrite it when `getMetadata()` throws, or returns the nested key:

```swift
let written2x: Bool
do {
    written2x = try await orders.getMetadata()?.customProperty("customProperties", as: [String: String].self) != nil
} catch KurrentError.internalParsingError {
    written2x = true   // a [high, low] duration or a string $acl: the server ignores the whole object
}
if written2x {
    let latest = client.streams(specified: "$$orders").read {
        $0.direction = .backward
        $0.revision = .end
        $0.limit = 1
    }
    for try await response in latest {
        let legacy = try JSONDecoder().decode(Legacy2xMetadata.self, from: response.event.record.data)
        try await orders.setMetadata(metadata: legacy.metadata())   // check $maxCount, $tb and $acl first
    }
}
```

The code assumes a 2.x Swift client wrote the stream's metadata: any metadata `getMetadata()` cannot read takes the rewrite path, and metadata another tool wrote with other top-level keys would be rewritten without them, so check what a stream holds before you rewrite it. A 2.x duration above the `maxAge(_:)` limit, 62,000,000,000 seconds, or the `cacheControl(_:)` limit, 922,337,203,685 seconds, stops the program at the builder's precondition: check `legacy.maxAge` and `legacy.cacheControl` first.

<doc:Stream-metadata> describes the 3.0 API, including custom keys of any JSON value with a `Codable` type.

## EventRecord throws KurrentError

In 2.x, creating an ``EventRecord`` threw the `EncodingError` of a payload that cannot be encoded as it was. In 3.0 the initializers throw ``KurrentError`` only: `EventRecord(eventType:payload:)`, `EventRecord(eventData:)` and the ones taking a ``CustomMetadata`` throw `KurrentError.underlyingError(reason:cause:)`, a new case that keeps the error from below the client as its `cause`. A `catch let error as EncodingError` around them still compiles but never matches.

```swift
// 2.x
do {
    let record = try EventRecord(eventType: "order-placed", payload: .json(OrderPlaced(orderId: "123")))
    print(record)
} catch let error as EncodingError {
    print("The payload cannot be encoded:", error)
}
```

```swift
// 3.0
do {
    let record = try EventRecord(eventType: "order-placed", payload: .json(OrderPlaced(orderId: "123")))
    print(record)
} catch {
    if let cause = error.cause as? EncodingError {
        print("The payload cannot be encoded:", cause)
    }
}
```

`cause` returns the error a ``KurrentError`` wraps, for `underlyingError` and for the cases that already carried one: `grpcError`, `grpcConnectionError`, `grpcRuntimeError` and `decodingError`. To match it in a `catch`, throw it again with `rethrowCause()`; an error that wraps none throws itself.

```swift
do {
    let record = try EventRecord(eventType: "order-placed", payload: .json(OrderPlaced(orderId: "123")))
    print(record)
} catch {
    do {
        try error.rethrowCause()
    } catch let cause as EncodingError {
        print("The payload cannot be encoded:", cause)
    } catch {
        print(error)
    }
}
```

A `switch` over every case of ``KurrentError`` needs a clause for `underlyingError`. The deprecated `EventRecord(eventType:payload:customMetadata:)` taking `Data` still throws `EncodingError` and `DecodingError` as on 2.6.2.

## Deprecated in 3.0

These still compile, with a deprecation warning, and behave as on 2.6.2 unless the note says otherwise. They are removed in 4.0.

| Deprecated | Use instead | Note |
|------------|-------------|------|
| `EventData(…, customMetadata:)` with `Data` or `nil`, in all four forms (`payload:`, `model:`, `data:`, `bytes:`) | `customMetadata: try .json(value)`, or `try CustomMetadata(data: data, format: .bytes)` | The same bytes are sent. For no metadata, leave the argument out. |
| `EventRecord(eventType:payload:customMetadata:)` with `Data` or `nil` | `customMetadata: try .json(value)`, or `try CustomMetadata(data: data, format: .json)` | The metadata must still be a JSON object. |
| `EventRecord.setValue(_:forKey:)` | Create the record with `customMetadata: .json(value)` | `setValue` stores the value unchecked, so one that cannot be sent fails at append; `.json(_:)` fails when the record is created. |
| Assigning to `EventRecord.properties` | As above | Reading `properties` is not deprecated. |
| `StreamMetadata.customProperties(_:)` with `[String: String]` | `customProperties(encoding:)` or `customProperty(_:encoding:)` | Merges the keys into the metadata, where 2.x replaced the whole custom dictionary. See "Stream metadata" above and <doc:Stream-metadata>. |

``CustomMetadata`` holds the bytes and the format they are written in. An ``EventData`` takes JSON or bytes; an ``EventRecord`` takes JSON only, and bytes metadata on a record is a compile error. To read metadata back, name the format: ``RecordedEvent/customMetadata(format:)``. `recordedEvent.customMetadata` still returns the stored `Data`.

## What did not change

Everything not listed above works as in 2.6.2. In particular:

- **`read().buffered`** fetches the whole result before it returns, as 2.x's `read()` did, with `defaultDeadline` bounding each attempt. Its type, `AsyncThrowingStream<ReadResponse, any Error>`, is unchanged; what it throws is under "Errors a read throws".
- **Catch-up subscriptions.** `subscribe` and `events` keep their API and deliver the same events, apart from the tombstone above and the error types under "Errors a read throws". Establishing a subscription is still not bounded by `defaultDeadline`.
- **Persistent subscriptions.** Their API, and how they deliver, acknowledge and report errors, are unchanged. Their errors are not mapped to `KurrentError` as a read's are: a `catch let error as RPCError` around one still matches.
- **Appends, deletes and the management calls** (projections, users, operations) keep their API, and `defaultDeadline` still bounds each attempt.
- **`ClientSettings`**, apart from the removed certificate members and what `defaultDeadline` means for `read()`. The default `operationRetryPolicy` is still two attempts without delay, and connection strings parse as in 2.6.

<doc:Reading-events> and <doc:Getting-started> describe the 3.0 API as a whole.
