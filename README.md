# swift-kurrentdb

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2Fswift-kurrentdb%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2Fswift-kurrentdb%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](Licence)
[![Swift Package Index](https://img.shields.io/badge/Swift%20Package%20Index-available-brightgreen)](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb)
[![Swift-build-testing](https://github.com/gradyzhuo/swift-kurrentdb/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/gradyzhuo/swift-kurrentdb/actions/workflows/swift-build-testing.yml)
[![codecov](https://codecov.io/gh/gradyzhuo/swift-kurrentdb/graph/badge.svg)](https://codecov.io/gh/gradyzhuo/swift-kurrentdb)

<div align=center>
<img src="https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:fikpipzuggbnuqew3treexnn/bafkreiadjakshxna7sn2gtwxdibew7e66vp3xplpghr72sxpwptsq7gf3i@jpeg" height="128px" width="128px" >
    
**A modern, type-safe Swift client for Kurrent (formerly EventStoreDB)**

Built for Server-Side Swift and Event Sourcing

[Documentation](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb) | [Getting Started](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/getting-started) | [Discussions](https://github.com/gradyzhuo/swift-kurrentdb/discussions)

</div>

---

## Why swift-kurrentdb?

Event Sourcing is a powerful pattern for building scalable, auditable systems. swift-kurrentdb brings this capability to the Swift ecosystem with a modern, type-safe client.

- **Native Swift** — Designed for Swift from the ground up, not a wrapper
- **Modern Concurrency** — Full async/await with Swift 6 data-race safety
- **Compile-Time Safety** — Swift 6 strict concurrency compliance with typed throws
- **Cluster-Ready** — First-class support for multi-node TLS clusters
- **Well-Documented** — Comprehensive guides on [Swift Package Index](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb)
- **Typed Errors** — All operations throw `KurrentError` for precise error handling

---

## Quick Start

### Installation

Add to your `Package.swift`:

<!-- snippet:skip -->
```swift
// 2.x — current stable, target-based API
dependencies: [
    .package(url: "https://github.com/gradyzhuo/swift-kurrentdb.git", from: "2.4.2")
]
```

> 🎉 **2.0 is here.** The target-based API is now the recommended way to use swift-kurrentdb —
> richer compile-time guarantees, better composability, and a cleaner surface area.
> See the [Migration Guide](#migration-guide) below for what's changed.
>
> **Already on 1.x?** Your existing code keeps working — the legacy flat-method API now ships
> as a separate `KurrentDB_V1` library in the same package, so you can migrate at your own pace.
> ```swift
> // Continue using the 1.x API without changes
> .package(url: "https://github.com/gradyzhuo/swift-kurrentdb.git", from: "1.12.2")
> ```

---

### Connect to a Cluster

```swift
import KurrentDB

// Local development — single node
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))

// Local development — multi-node TLS cluster
let localCluster = ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .certificate(path: "/path/to/ca.crt")

// Production — remote cluster (TLS enabled by default)
let production = ClientSettings.remote(
    "node1.example.com:2113",
    "node2.example.com:2113",
    "node3.example.com:2113"
).authenticated(.credentials(username: "admin", password: "changeit"))

// Connection string
let fromString: ClientSettings = "kurrentdb://admin:changeit@node1:2113,node2:2113?tls=true"

// From an environment variable (defaults to SWIFT_KURRENT_DB_URL)
let fromEnvironment = try ClientSettings.fromEnv()

let client = KurrentDBClient(settings: settings)
```

Create one client per application and reuse it. Calls that return a single response — appends, deletes, metadata, management operations — share one connection per node. Calls that return a stream — reads and subscriptions — each get their own connection, so long-lived subscriptions never compete with other calls for capacity. `client.shutdown()` closes every connection the client opened and makes further calls throw `KurrentError.connectionClosed`; calling it again does nothing.

Need a database per test? The `KurrentDBPool` library lends out clients for a set of independent KurrentDB instances, one caller per instance at a time — see [Client pools](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/client-pools).

---

### Append and Read Events

```swift
struct OrderPlaced: Codable, Sendable {
    let orderId: String
    let total: Double
}

// Create an event
let event = EventData(
    eventType: "OrderPlaced",
    model: OrderPlaced(orderId: "order-123", total: 99.99)
)

// Append to stream
try await client.streams(specified: "orders").append(events: [event]) {
    $0.expectedRevision = .any
}

// Read events
let responses = try await client.streams(specified: "orders").read {
    $0.revision = .start
    $0.limit = 10
}

for try await response in responses {
    let readEvent = try response.event
    print("Event: \(readEvent.record.eventType)")
}
```

---

## API Overview

### Streams

```swift
// Append
try await client.streams(specified: "orders").append(events: [event]) {
    $0.expectedRevision = .streamExists
}

// Read forward
let forward = try await client.streams(specified: "orders").read {
    $0.revision = .start
    $0.limit = 50
}

// Read backward
let backward = try await client.streams(specified: "orders").read {
    $0.revision = .end
    $0.direction = .backward
    $0.limit = 10
}

// Read $all
let allResponses = try await client.allStreams.read {
    $0.limit = 100
}

// Read $all with server-side filtering
let filtered = try await client.allStreams.read {
    $0.filter = .onEventType(prefixes: "OrderPlaced")
}

// Subscribe (catch-up)
let subscription = try await client.streams(specified: "orders").subscribe()
for try await readEvent in subscription.events {
    print(readEvent.record.eventType)
}

// Subscribe to $all, filtered on the server
let allSubscription = try await client.allStreams.subscribe {
    $0.filter = .onStreamName(prefixes: ["order-"])
}

// Delete / tombstone
try await client.streams(specified: "orders").delete()
try await client.streams(specified: "orders").tombstone()

// Stream metadata
try await client.streams(specified: "orders").setMetadata(metadata: StreamMetadata().maxCount(1000))
let metadata = try await client.streams(specified: "orders").getMetadata()
```

### Multi-stream writes

```swift
let record = try EventRecord(eventType: "OrderPlaced", payload: .json(OrderPlaced(orderId: "order-1", total: 10)))

// Atomic multi-stream append (KurrentDB 25.1+).
try await client.multiStreams.append(events: [
    StreamEvent(stream: "order-1", records: [record]),
    StreamEvent(stream: "inventory-1", records: [record]),
])

// AppendRecords — atomic multi-stream append with Dynamic Consistency Boundary
// checks on any stream (KurrentDB 26.1+).
try await client.multiStreams.appendRecords(
    events: [
        StreamEvent(stream: "order-1", records: [record]),
        StreamEvent(stream: "inventory-1", records: [record]),
    ],
    checks: [.streamState("order-1", .streamExists)]
)

// BatchAppend — high-throughput pipelined append; non-atomic, per-item results.
let batch = try await client.multiStreams.batchAppend(events: [
    StreamEvent(stream: "orders", records: [record]),
    StreamEvent(stream: "audit", records: [record]),
])
```

### Per-call credentials

```swift
// Override authentication for a single operation (multi-tenant / per-request auth).
try await client.streams(specified: "orders")
    .authenticated(.credentials(username: "svc", password: "secret"))
    .append(events: [event])

// Bearer token authentication is also supported.
try await client.streams(specified: "orders")
    .authenticated(.bearer(token: "<token>"))
    .append(events: [event])
```

### Projections

```swift
let js = "fromAll().when({ $any: function(s, e) { s.count = (s.count || 0) + 1; } }).outputState();"

// Create
try await client.projections(of: .continuous(name: "order-count")).create(query: js)
try await client.projections(of: .onetime).create(query: js)
try await client.projections(of: .transient(name: "temp")).create(query: js)

// Lifecycle
try await client.projections(name: "order-count").enable()
try await client.projections(name: "order-count").disable()
try await client.projections(name: "order-count").abort()
try await client.projections(name: "order-count").reset()
try await client.projections(name: "order-count").delete()

// Query state / result
struct CountResult: Codable { let count: Int }
let state: CountResult? = try await client.projections(name: "order-count").state(of: CountResult.self)
let result: Int? = try await client.projections(name: "order-count").result(of: Int.self)

// List
let continuous = try await client.projections(of: .anyContinuous).list()
let all = try await client.projections(of: .anyMode).list()
```

### Persistent Subscriptions

```swift
// Create a subscription group
try await client.persistentSubscriptions(stream: "orders", group: "order-workers").create {
    $0.revision = .start
    $0.settings.maxRetryCount = 5
}

// Subscribe and process events
let subscription = try await client.persistentSubscriptions(
    stream: "orders",
    group: "order-workers"
).subscribe()

for try await result in subscription.events {
    do {
        // handle event via result.event.record
        try await subscription.ack(readEvents: result.event)
    } catch {
        try await subscription.nack(readEvents: result.event, action: .park, reason: "\(error)")
    }
}

// $all persistent subscription
try await client.persistentSubscriptions(filterGroup: "all-workers").create()
let allSub = try await client.persistentSubscriptions(filterGroup: "all-workers").subscribe()

// Update / delete
try await client.persistentSubscriptions(stream: "orders", group: "order-workers").update()
try await client.persistentSubscriptions(stream: "orders", group: "order-workers").delete()
```

### User Management

```swift
// Create a user
try await client.users.create(
    loginName: "jane",
    password: "secure_password",
    fullName: "Jane Doe",
    groups: ["ops"]
)

// Manage user
try await client.user("jane").enable()
try await client.user("jane").disable()
try await client.user("jane").change(password: "new", origin: "old")
try await client.user("jane").reset(password: "reset")
```

### Server Operations

```swift
// Scavenge
let response = try await client.operations(of: .scavenge).startScavenge(threadCount: 2, startFromChunk: 0)
try await client.operations(of: .activeScavenge(scavengeId: response.scavengeId)).stopScavenge()

// System
try await client.operations(of: .system).mergeIndexes()
try await client.operations(of: .system).restartPersistentSubscriptions()

// Node
try await client.operations(of: .node).resignNode()
try await client.operations(of: .node).setNodePriority(priority: 10)
```

### Cluster Gossip

```swift
let members = try await client.readCluster()

for member in members {
    print("\(member.httpEndPoint.host):\(member.httpEndPoint.port) — \(member.state)")
}

if let leader = members.first(where: { $0.state == .leader && $0.isAlive }) {
    print("Leader: \(leader.httpEndPoint)")
}
```

### Monitoring

```swift
let stats = try await client.stats(refreshTimePeriodInMs: 5000)

for try await snapshot in stats {
    print("Metrics: \(snapshot.stats.count) entries")
}
```

---

## Migration Guide

**Version 2.0.0** introduces a breaking redesign of the API.
The flat methods on `KurrentDBClient` are replaced by a **target-based, hierarchical** style:

<!-- snippet:skip -->
```swift
// 1.x
try await client.appendToStream("orders", events: [event]) { ... }
```

```swift
// 2.x
try await client.streams(of: .specified("orders")).append(events: [event]) {
    $0.expectedRevision = .streamExists
}
```

### The 1.x API moves to `KurrentDB_V1`

In 2.x the old flat-method API is **no longer part of the `KurrentDB` module**.
It has been moved to a separate `KurrentDB_V1` library that ships in the same package.
If you are not ready to migrate immediately, switch your dependency target and import:

<!-- snippet:skip -->
```swift
// Package.swift
.product(name: "KurrentDB_V1", package: "swift-kurrentdb")
```

<!-- snippet:skip -->
```swift
// Replace your existing import
import KurrentDB_V1   // was: import KurrentDB
```

`KurrentDB_V1` gives you access to all 1.x methods (marked `@deprecated`) while you migrate to the new API at your own pace.

👉 [Full Migration Guide — 1.x to 2.x](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/migration-guide)

---

## Features

| Category | Operations |
|----------|-----------|
| **Streams** | Append, read, delete, tombstone, metadata, subscribe (catch-up), $all stream with server-side filtering |
| **Multi-stream writes** | Atomic multi-stream append, AppendRecords (Dynamic Consistency Boundary), BatchAppend |
| **Persistent Subscriptions** | Create, subscribe, update, delete, ACK/NAK, $all support |
| **Projections** | Create (continuous/one-time/transient), enable, disable, state, result |
| **Users** | Create, enable, disable, update, change/reset password |
| **Operations** | Scavenge (start/stop), merge indexes, shutdown, node priority |
| **Gossip** | Cluster discovery, node health, leader detection |
| **Monitoring** | Real-time server statistics |
| **Connection** | TLS/SSL, cluster gossip discovery, auto-reconnection, keep-alive, shared/dedicated connection management |
| **Authentication** | Username/password, bearer tokens, per-call credential overrides |
| **Client pools** | `KurrentDBPool` — borrow a client for one of several independent KurrentDB instances (e.g. per test) |

## Test Coverage

Coverage is measured on every CI run against a live 3-node TLS KurrentDB cluster and published to [Codecov](https://codecov.io/gh/gradyzhuo/swift-kurrentdb).

### Test Suites

| Suite | Type | Key Scenarios |
|-------|------|---------------|
| **StreamsTests** | Integration | Append, read (forward/backward/limit/revision), subscribe, metadata, optimistic concurrency, delete, tombstone, multi-stream append, AppendRecords, BatchAppend, filtered `$all` reads |
| **ProjectionsTests** | Integration | Create (continuous/one-time/transient), enable/disable, abort, reset, state/result query, list |
| **PersistentSubscriptionsTests** | Integration | Create, subscribe, ACK, NACK (park/retry), getInfo, update settings, list, delete, replay parked, connection teardown |
| **UsersTests** | Integration | Create, enable/disable, update, change/reset password |
| **OperationsTests** | Integration | Scavenge (start/stop), merge indexes, restart persistent subscriptions, node priority, resign |
| **GossipTests** | Integration | Read cluster members, node state, custom timeout |
| **MonitoringTests** | Integration | Server stats, refresh interval, metadata flag |
| **KurrentDBPoolTests** | Integration | Borrowing, waiting, env configuration against independent instances |
| **KurrentCoreTests** | Unit | Connection string parsing, `EventData`, projection status, stream identifiers, metadata, stream filters |
| **MockClientTests** | Mock/DI | `KurrentDBClientProtocol` conformance, all factory call patterns, domain service scenarios |
| **DocSnippetsTests** | Build | Every Swift example in this README and the DocC articles compiles |

### Optimistic Concurrency

Streams write-side error paths are explicitly covered:

| Scenario | Expected Error |
|----------|---------------|
| Append at stale revision (`.at(99)`, stream at 0) | `wrongExpectedVersion` |
| Append with `.noStream` to an existing stream | `wrongExpectedVersion` |
| Two concurrent writers at the same revision | One succeeds, one `wrongExpectedVersion` |

### Persistent Subscription Lifecycle

| Scenario | Verified |
|----------|---------|
| Create → subscribe → append → ACK | ✓ |
| NACK with park (dead-letter queue) | ✓ |
| NACK with retry (re-delivery, deliveries == 2) | ✓ |
| getInfo (groupName, eventSource, $all) | ✓ |
| Update settings → getInfo confirms change | ✓ |
| park → replayParked → re-delivered → ACK | ✓ |
| Dropping the subscription handle closes its connection | ✓ |

## Requirements

- Swift 6.0+
- macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+ / Linux

### KurrentDB Server Compatibility

| Server Version | Status | Notes |
|:--------------:|:------:|-------|
| **KurrentDB 26.1** | ✅ Supported | Full feature support |
| **KurrentDB 26.0** | ✅ Supported | Everything except AppendRecords (26.1+) |
| **KurrentDB 25.1** | ✅ Supported | Everything except AppendRecords (26.1+) |
| **EventStoreDB 24.x** | ✅ Supported | Core features; no multi-stream append or AppendRecords |

### Local Development with Docker

Start a 3-node TLS cluster:

```bash
cd server
docker compose up -d
```

This generates TLS certificates automatically and starts nodes on ports 2111, 2112, and 2113.

Or a single insecure node for quick testing:

```bash
docker run --rm -d -p 2113:2113 \
  -e KURRENTDB_CLUSTER_SIZE=1 \
  -e KURRENTDB_RUN_PROJECTIONS=All \
  -e KURRENTDB_START_STANDARD_PROJECTIONS=true \
  -e KURRENTDB_INSECURE=true \
  -e KURRENTDB_ENABLE_ATOM_PUB_OVER_HTTP=true \
  docker.kurrent.io/kurrent-latest/kurrentdb:25.1
```

## Documentation

| Guide | Description |
|-------|-------------|
| [Migration Guide (1.x → 2.x)](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/migration-guide) | What changed in 2.0 and how to update your code |
| [Getting Started](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/getting-started) | Connection settings, first event, basic usage |
| [Appending Events](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/appending-events) | EventData, concurrency control, idempotency, multi-stream writes |
| [Reading Events](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/reading-events) | Forward/backward reading, $all stream, server-side filters |
| [Projections](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/managing-projections) | Create, manage, and query projection state |
| [Persistent Subscriptions](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/persistent-subscriptions) | Competing consumers, ACK/NAK, subscription groups |
| [User Management](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/user-management) | Create, enable, disable, password management |
| [Cluster Gossip](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/cluster-gossip) | Cluster discovery, node health monitoring |
| [Monitoring](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/server-statistics) | Real-time server statistics |
| [Server Operations](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/server-operations) | Scavenge, index merge, shutdown, node management |
| [Client Pools](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/client-pools) | `KurrentDBPool`: borrow a client per test from independent instances |
| [Full API Reference](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb) | Complete API documentation |

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, documentation improvements, or code contributions.

- [GitHub Discussions](https://github.com/gradyzhuo/swift-kurrentdb/discussions) — Ask questions, share ideas
- [Issues](https://github.com/gradyzhuo/swift-kurrentdb/issues) — Report bugs
- [Contributing Guide](CONTRIBUTING.md) — Get started contributing

## License

MIT License — see [Licence](Licence) for details.

---

Made by [Grady Zhuo](https://github.com/gradyzhuo)
