# Migrating from 1.x to 2.x

Learn how to update your code from the 1.x flat-method API to the 2.x target-based API.

## Overview

Version 2.x introduces a **target-based, hierarchical API** that replaces the flat method calls of 1.x. The core idea is:

1. Call a *factory method* on `KurrentDBClient` to get a scoped service object (the "target").
2. Call the operation you want on that object.

This makes the API more composable, type-safe, and easier to discover — the compiler guides you to the operations that are valid for the scope you've selected.

> **1.x code is migrated on 2.6.** The `KurrentDB_V1` library that carried the 1.x methods ships in 2.x only. Pin `from: "2.6.0"`, follow this guide with its documentation at [/2.6/documentation/kurrentdb/migration-guide](https://gradyzhuo.github.io/swift-kurrentdb/2.6/documentation/kurrentdb/migration-guide), and move to 3.0 once nothing imports `KurrentDB_V1` — 3.0 has no `KurrentDB_V1`.
>
> **One call keeps compiling with a different meaning: `client.shutdown()`.** `KurrentDB_V1` added an `async` `shutdown()` that shuts the *server* down. Once no file in your module and no module you depend on imports `KurrentDB_V1`, the same line binds to `KurrentDBClient.shutdown()`, which only closes this client. It still compiles: at most with warnings about an unnecessary `await` (and, from 3.0, `try`), with no warning at all when `client.shutdown` is passed as a function value, with none about the `await` when its receiver is itself awaited, and with none about the `try` or the `await` while another call in the same expression still needs it. Do not count on a warning to find these lines. On 2.6 every such call still shows the `KurrentDB_V1` deprecation warning, so sort them before you delete the import. One use shows none: if `KurrentDBClient` conforms to a protocol of yours that requires `func shutdown() async throws`, `KurrentDB_V1`'s method meets the requirement while the module is imported, and `KurrentDBClient.shutdown()` meets it once the import is gone, both without a warning, so a call through that protocol stops shutting the server down and closes the client instead. Find those conformances yourself. Rewrite each one that means "shut the server down" as `try await client.operations(of: .system).shutdown()`. Leave each one that means "close this client" as it is: while `KurrentDB_V1` is imported, `try client.shutdown()` in async code does not compile, and its fix-it adds back the `await` that selects the server shutdown, so those lines keep shutting the server down until the import is gone, as they always did. After that they bind to `KurrentDBClient.shutdown()`; remove what the compiler flags as unnecessary. Inside a function declared `throws(KurrentError)` such a line stops compiling instead, because `KurrentDBClient.shutdown()` throws an untyped error; write `do { try client.shutdown() } catch { … }` and decide there what a failure to close means.

---

## Client creation

No change here. Creating a `KurrentDBClient` is identical in both versions.

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))

let client = KurrentDBClient(settings: settings)
```

---

## ClientSettings — certificate spelling fix

The `cerificates` property and `cerificate(source:)` / `cerificate(path:)` builder methods were misspelled in 1.x. They are corrected in 2.x and the old names, deprecated in 2.x, are removed in 3.0.

In 2.5, `certificate(path:)` (and its alias `cerificate(path:)`) is deprecated as well (when its file cannot be read, the client refuses to connect instead of trusting the system's root certificates) and removed in 3.0. Use `certificate(path:fallback:)`, which throws right away (`fallback: .none`) or, only when you ask for it, leaves the file out (`fallback: .systemTrustRoots`).

<!-- snippet:skip -->
```swift
// 1.x (misspelled — deprecated in 2.x, removed in 3.0)
settings.cerificate(source: .crtInBundle("ca")!)
```

```swift
// 2.x (correct)
let withCertificate = settings.certificate(source: .crtInBundle("ca")!)
```

---

## Options builder pattern

In 1.x, options were configured by chaining methods that each returned `Self`:

<!-- snippet:skip -->
```swift
// 1.x
let options = StreamsReadOptions()
    .limit(10)
    .backward()
    .startFrom(revision: .end)
```

In 2.x, options are configured through an `inout` closure passed directly to the operation:

```swift
// 2.x
let responses = try await client.streams(specified: "orders").read {
    $0.limit = 10
    $0.direction = .backward
    $0.revision = .end
}
```

---

## Streams

### Appending events

<!-- snippet:skip -->
```swift
// 1.x
try await client.appendToStream("orders", events: [eventData]) {
    $0.revision(expected: .streamExists)
}
```

```swift
// 2.x
try await client.streams(of: .specified("orders")).append(events: [eventData]) {
    $0.expectedRevision = .streamExists
}
```

### Reading from a stream

<!-- snippet:skip -->
```swift
// 1.x
let responses = try await client.readStream("orders") {
    $0.limit(10).backward().startFrom(revision: .end)
}
```

```swift
// 2.x
let responses = try await client.streams(of: .specified("orders")).read {
    $0.limit = 10
    $0.direction = .backward
    $0.revision = .end
}
```

### Reading from $all

<!-- snippet:skip -->
```swift
// 1.x
let responses = try await client.readAllStreams {
    $0.limit(50)
}
```

```swift
// 2.x
let responses = try await client.allStreams.read {
    $0.limit = 50
}
```

### Subscribing to a stream

<!-- snippet:skip -->
```swift
// 1.x
let subscription = try await client.subscribeStream("orders")
```

```swift
// 2.x
let subscription = try await client.streams(of: .specified("orders")).subscribe()
```

### Subscribing to $all

<!-- snippet:skip -->
```swift
// 1.x
let subscription = try await client.subscribeAllStreams()
```

```swift
// 2.x
let subscription = try await client.allStreams.subscribe()
```

### Deleting / tombstoning a stream

<!-- snippet:skip -->
```swift
// 1.x
try await client.deleteStream("orders")
try await client.tombstoneStream("orders")
```

```swift
// 2.x
try await client.streams(of: .specified("orders")).delete()
try await client.streams(of: .specified("orders")).tombstone()
```

### Stream metadata

<!-- snippet:skip -->
```swift
// 1.x
try await client.setStreamMetadata("orders", metadata: metadata)
let metadata = try await client.getStreamMetadata("orders")
```

```swift
// 2.x
try await client.streams(of: .specified("orders")).setMetadata(metadata: StreamMetadata().maxCount(1000))
let metadata = try await client.streams(of: .specified("orders")).getMetadata()
```

### Convenience shorthands

```swift
// 2.x provides convenience accessors
client.streams(specified: "orders")   // same as .streams(of: .specified("orders"))
client.allStreams                      // same as .streams(of: .all)
client.multiStreams                    // multi-stream writes: append, appendRecords, batchAppend
```

---

## Projections

### Create

<!-- snippet:skip -->
```swift
// 1.x
try await client.createContinuousProjection(name: "by-order", query: js)
try await client.createOneTimeProjection(query: js)
try await client.createTransientProjection(name: "temp", query: js)
```

```swift
// 2.x
try await client.projections(of: .continuous(name: "by-order")).create(query: js)
try await client.projections(of: .onetime).create(query: js)
try await client.projections(of: .transient(name: "temp")).create(query: js)
```

### Lifecycle operations

<!-- snippet:skip -->
```swift
// 1.x
try await client.enableProjection(name: "by-order")
try await client.disableProjection(name: "by-order")
try await client.abortProjection(name: "by-order")
try await client.resetProjection(name: "by-order")
try await client.deleteProjection(name: "by-order")
```

```swift
// 2.x
let proj = client.projections(name: "by-order")
try await proj.enable()
try await proj.disable()
try await proj.abort()
try await proj.reset()
try await proj.delete()
```

### Query result / state

<!-- snippet:skip -->
```swift
// 1.x
let result: MyResult? = try await client.getProjectionResult(of: MyResult.self, name: "by-order")
let state: MyState? = try await client.getProjectionState(of: MyState.self, name: "by-order")
```

```swift
// 2.x
let result: MyResult? = try await client.projections(name: "by-order").result(of: MyResult.self)
let state: MyState? = try await client.projections(name: "by-order").state(of: MyState.self)
```

### Detail & listing

<!-- snippet:skip -->
```swift
// 1.x
let detail = try await client.getProjectionDetail(name: "by-order")
let all = try await client.listAllProjections(mode: .continuous)
```

```swift
// 2.x
let detail = try await client.projections(name: "by-order").detail()
let all = try await client.projections(of: .anyMode).list()
```

### System projections

```swift
// 2.x — new in 2.x, no direct equivalent in 1.x
try await client.projections(system: .byCategory).enable()
try await client.projections(system: .streamByCategory).enable()
```

---

## Persistent subscriptions

### Create

<!-- snippet:skip -->
```swift
// 1.x
try await client.createPersistentSubscription(stream: "orders", groupName: "workers")
try await client.createPersistentSubscriptionToAllStream(groupName: "all-workers")
```

```swift
// 2.x
try await client.persistentSubscriptions(stream: "orders", group: "workers").create()
try await client.persistentSubscriptions(filterGroup: "all-workers").create()
```

### Subscribe & acknowledge

<!-- snippet:skip -->
```swift
// 1.x
let subscription = try await client.subscribePersistentSubscription(
    stream: "orders", groupName: "workers"
)
for try await result in subscription.events {
    try await subscription.ack(readEvents: result.event)
}
```

```swift
// 2.x
let subscription = try await client.persistentSubscriptions(
    stream: "orders", group: "workers"
).subscribe()

for try await result in subscription.events {
    try await subscription.ack(readEvents: result.event)
}
```

> The `Subscription` object itself (including `ack`, `nack`, `events`) is unchanged between versions.

### Handling subscription drop (new in 2.x)

In 2.x, when the server drops the subscription, the `events` stream throws `KurrentError.subscriptionDropped` instead of ending silently:

<!-- snippet:continue -->
```swift
do {
    for try await result in subscription.events {
        try await subscription.ack(readEvents: result.event)
    }
} catch let KurrentError.subscriptionDropped(reason, lastRevision, lastPosition) {
    // Resume from lastRevision (stream subscription) or lastPosition ($all subscription)
    print("Dropped: \(reason), lastRevision: \(String(describing: lastRevision))")
}
```

### Delete & update

<!-- snippet:skip -->
```swift
// 1.x
try await client.deletePersistentSubscription(stream: "orders", groupName: "workers")
try await client.updatePersistentSubscription(stream: "orders", groupName: "workers") { $0 }
```

```swift
// 2.x
try await client.persistentSubscriptions(stream: "orders", group: "workers").delete()
try await client.persistentSubscriptions(stream: "orders", group: "workers").update()
```

### Listing

<!-- snippet:skip -->
```swift
// 1.x
let list = try await client.listAllPersistentSubscription()
```

```swift
// 2.x
let list = try await client.allPersistentSubscriptions.list()
```

---

## Users

### Create & manage

<!-- snippet:skip -->
```swift
// 1.x
try await client.createUser(loginName: "alice", password: "secret", fullName: "Alice", groups: ["admins"])
try await client.enableUser(loginName: "alice")
try await client.disableUser(loginName: "alice")
try await client.changeUserPassword(loginName: "alice", currentPassword: "secret", newPassword: "new")
try await client.resetUserPassword(loginName: "alice", newPassword: "reset")
```

```swift
// 2.x
try await client.users.create(loginName: "alice", password: "secret", fullName: "Alice", groups: ["admins"])
try await client.user("alice").enable()
try await client.user("alice").disable()
try await client.user("alice").change(password: "new", origin: "secret")
try await client.user("alice").reset(password: "reset")
```

---

## Server operations

### Scavenge

<!-- snippet:skip -->
```swift
// 1.x
let response = try await client.startScavenge(threadCount: 1, startFromChunk: 0)
try await client.stopScavenge(scavengeId: response.scavengeId)
```

```swift
// 2.x
let response = try await client.operations(of: .scavenge).startScavenge(threadCount: 1, startFromChunk: 0)
try await client.operations(of: .activeScavenge(scavengeId: response.scavengeId)).stopScavenge()
```

### Other operations

<!-- snippet:skip -->
```swift
// 1.x
try await client.mergeIndexes()
try await client.restartPersistentSubscriptions()
try await client.resignNode()
try await client.setNodePriority(priority: 3)
```

```swift
// 2.x
try await client.operations(of: .system).mergeIndexes()
try await client.operations(of: .system).restartPersistentSubscriptions()
try await client.operations(of: .node).resignNode()
try await client.operations(of: .node).setNodePriority(priority: 3)
```

---

## Quick reference table

| 1.x | 2.x |
|-----|-----|
| `client.appendToStream("s", events:)` | `client.streams(of: .specified("s")).append(events:)` |
| `client.readStream("s")` | `client.streams(of: .specified("s")).read()` |
| `client.readAllStreams()` | `client.allStreams.read()` |
| `client.subscribeStream("s")` | `client.streams(of: .specified("s")).subscribe()` |
| `client.subscribeAllStreams()` | `client.allStreams.subscribe()` |
| `client.deleteStream("s")` | `client.streams(of: .specified("s")).delete()` |
| `client.tombstoneStream("s")` | `client.streams(of: .specified("s")).tombstone()` |
| `client.setStreamMetadata("s", metadata:)` | `client.streams(of: .specified("s")).setMetadata(metadata:)` |
| `client.getStreamMetadata("s")` | `client.streams(of: .specified("s")).getMetadata()` |
| `client.createContinuousProjection(name:, query:)` | `client.projections(of: .continuous(name)).create(query:)` |
| `client.enableProjection(name:)` | `client.projections(name: name).enable()` |
| `client.getProjectionResult(of:, name:)` | `client.projections(name: name).result(of:)` |
| `client.createPersistentSubscription(stream:, groupName:)` | `client.persistentSubscriptions(stream:, group:).create()` |
| `client.subscribePersistentSubscription(stream:, groupName:)` | `client.persistentSubscriptions(stream:, group:).subscribe()` |
| `client.createUser(loginName:, ...)` | `client.users.create(loginName:, ...)` |
| `client.enableUser(loginName:)` | `client.user(loginName).enable()` |
| `client.startScavenge(...)` | `client.operations(of: .scavenge).startScavenge(...)` |
| `client.mergeIndexes()` | `client.operations(of: .system).mergeIndexes()` |
| `client.shutdown()` (`KurrentDB_V1`; shuts the server down) | To stop the server: `client.operations(of: .system).shutdown()`. To close the client: `client.shutdown()` — from synchronous code it always closes the client; from async code only once nothing imports `KurrentDB_V1` (see the box at the top) |
| `client.resignNode()` | `client.operations(of: .node).resignNode()` |
| `settings.cerificate(source:)` *(misspelled)* | `settings.certificate(source:)` (the misspelled name is removed in 3.0) |
