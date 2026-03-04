# Migrating from 1.x to 2.x

Learn how to update your code from the 1.x flat-method API to the 2.x target-based API.

## Overview

Version 2.x introduces a **target-based, hierarchical API** that replaces the flat method calls of 1.x. The core idea is:

1. Call a *factory method* on `KurrentDBClient` to get a scoped service object (the "target").
2. Call the operation you want on that object.

This makes the API more composable, type-safe, and easier to discover — the compiler guides you to the operations that are valid for the scope you've selected.

> **Important — the 1.x API moves to `KurrentDB_V1`**
>
> In 2.x, the old flat-method API is no longer part of the `KurrentDB` module.
> It has been moved to a separate `KurrentDB_V1` library that ships in the same package.
> If you are not ready to migrate, update your dependency target and import:
>
> ```swift
> // Package.swift — add KurrentDB_V1 to your target dependencies
> .product(name: "KurrentDB_V1", package: "swift-kurrentdb")
> ```
>
> ```swift
> // Replace your existing import
> import KurrentDB_V1   // was: import KurrentDB
> ```
>
> `KurrentDB_V1` gives you access to all 1.x methods (marked `@deprecated`) while you migrate to 2.x at your own pace.
> The `KurrentDBClient` type and `ClientSettings` are shared between both modules, so no changes to client creation are needed.

All 1.x methods in `KurrentDB_V1` carry `@deprecated` annotations with Xcode fix-its pointing to their 2.x equivalents, making incremental migration straightforward.

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

The `cerificates` property and `cerificate(source:)` / `cerificate(path:)` builder methods were misspelled in 1.x. They are corrected in 2.x and the old names are kept as deprecated aliases.

```swift
// 1.x (misspelled — still compiles but emits a deprecation warning)
settings.cerificate(source: .crtInBundle("ca", inBundle: .module)!)

// 2.x (correct)
settings.certificate(source: .crtInBundle("ca", inBundle: .module)!)
```

---

## Options builder pattern

In 1.x, options were configured by chaining methods that each returned `Self`:

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
try await stream.read {
    $0.maxCount = 10
    $0.direction = .backward
    $0.revision = .end
}
```

---

## Streams

### Appending events

```swift
// 1.x
try await client.appendToStream("orders", events: [eventData]) {
    $0.revision(expected: .streamExists)
}

// 2.x
try await client.streams(of: .specified("orders")).append(events: [eventData]) {
    $0.expectedRevision = .streamExists
}
```

### Reading from a stream

```swift
// 1.x
let responses = try await client.readStream("orders") {
    $0.limit(10).backward().startFrom(revision: .end)
}

// 2.x
let responses = try await client.streams(of: .specified("orders")).read {
    $0.maxCount = 10
    $0.direction = .backward
    $0.revision = .end
}
```

### Reading from $all

```swift
// 1.x
let responses = try await client.readAllStreams {
    $0.limit(50)
}

// 2.x
let responses = try await client.allStreams.read {
    $0.maxCount = 50
}
```

### Subscribing to a stream

```swift
// 1.x
let subscription = try await client.subscribeStream("orders")

// 2.x
let subscription = try await client.streams(of: .specified("orders")).subscribe()
```

### Subscribing to $all

```swift
// 1.x
let subscription = try await client.subscribeAllStreams()

// 2.x
let subscription = try await client.allStreams.subscribe()
```

### Deleting / tombstoning a stream

```swift
// 1.x
try await client.deleteStream("orders")
try await client.tombstoneStream("orders")

// 2.x
try await client.streams(of: .specified("orders")).delete()
try await client.streams(of: .specified("orders")).tombstone()
```

### Stream metadata

```swift
// 1.x
try await client.setStreamMetadata("orders", metadata: metadata)
let metadata = try await client.getStreamMetadata("orders")

// 2.x
try await client.streams(of: .specified("orders")).setMetadata(metadata: metadata)
let metadata = try await client.streams(of: .specified("orders")).getMetadata()
```

### Convenience shorthands

```swift
// 2.x provides convenience accessors
client.streams(specified: "orders")   // same as .streams(of: .specified("orders"))
client.allStreams                      // same as .streams(of: .all)
client.multiStreams                    // multi-stream batch (KurrentDB 25.1+)
```

---

## Projections

### Create

```swift
// 1.x
try await client.createContinuousProjection(name: "by-order", query: js)
try await client.createOneTimeProjection(query: js)
try await client.createTransientProjection(name: "temp", query: js)

// 2.x
try await client.projections(of: .continuous("by-order")).create(query: js)
try await client.projections(of: .onetime).create(query: js)
try await client.projections(of: .transient("temp")).create(query: js)
```

### Lifecycle operations

```swift
// 1.x
try await client.enableProjection(name: "by-order")
try await client.disableProjection(name: "by-order")
try await client.abortProjection(name: "by-order")
try await client.resetProjection(name: "by-order")
try await client.deleteProjection(name: "by-order")

// 2.x
let proj = client.projections(name: "by-order")
try await proj.enable()
try await proj.disable()
try await proj.abort()
try await proj.reset()
try await proj.delete()
```

### Query result / state

```swift
// 1.x
let result: MyResult? = try await client.getProjectionResult(of: MyResult.self, name: "by-order")
let state: MyState? = try await client.getProjectionState(of: MyState.self, name: "by-order")

// 2.x
let result: MyResult? = try await client.projections(name: "by-order").result(of: MyResult.self)
let state: MyState? = try await client.projections(name: "by-order").state(of: MyState.self)
```

### Detail & listing

```swift
// 1.x
let detail = try await client.getProjectionDetail(name: "by-order")
let all = try await client.listAllProjections(mode: .continuous)

// 2.x
let detail = try await client.projections(name: "by-order").detail()
let all = try await client.projections(of: .anyMode).list()
```

### System projections

```swift
// 2.x — new in 2.x, no direct equivalent in 1.x
try await client.projections(system: .byCategory).enable()
try await client.projections(system: .streamByType).enable()
```

---

## Persistent subscriptions

### Create

```swift
// 1.x
try await client.createPersistentSubscription(stream: "orders", groupName: "workers")
try await client.createPersistentSubscriptionToAllStream(groupName: "all-workers")

// 2.x
try await client.persistentSubscriptions(stream: "orders", group: "workers").create()
try await client.allPersistentSubscriptions.create()  // uses group configured via closure
```

### Subscribe & acknowledge

```swift
// 1.x
let subscription = try await client.subscribePersistentSubscription(
    stream: "orders", groupName: "workers"
)
for try await result in subscription.events {
    try await subscription.ack(readEvents: result.event)
}

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

```swift
// 1.x
try await client.deletePersistentSubscription(stream: "orders", groupName: "workers")
try await client.updatePersistentSubscription(stream: "orders", groupName: "workers") { $0 }

// 2.x
try await client.persistentSubscriptions(stream: "orders", group: "workers").delete()
try await client.persistentSubscriptions(stream: "orders", group: "workers").update()
```

### Listing

```swift
// 1.x
let list = try await client.listAllPersistentSubscription()

// 2.x
let list = try await client.allPersistentSubscriptions.list()
```

---

## Users

### Create & manage

```swift
// 1.x
try await client.createUser(loginName: "alice", password: "secret", fullName: "Alice", groups: ["admins"])
try await client.enableUser(loginName: "alice")
try await client.disableUser(loginName: "alice")
try await client.changeUserPassword(loginName: "alice", currentPassword: "secret", newPassword: "new")
try await client.resetUserPassword(loginName: "alice", newPassword: "reset")

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

```swift
// 1.x
let response = try await client.startScavenge(threadCount: 1, startFromChunk: 0)
try await client.stopScavenge(scavengeId: response.scavengeId)

// 2.x
let response = try await client.operations(of: .scavenge).startScavenge(threadCount: 1, startFromChunk: 0)
try await client.operations(of: .activeScavenge(scavengeId: response.scavengeId)).stopScavenge()
```

### Other operations

```swift
// 1.x
try await client.mergeIndexes()
try await client.restartPersistentSubscriptions()
try await client.resignNode()
try await client.setNodePriority(priority: 3)

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
| `client.resignNode()` | `client.operations(of: .node).resignNode()` |
| `settings.cerificate(source:)` *(misspelled)* | `settings.certificate(source:)` |
