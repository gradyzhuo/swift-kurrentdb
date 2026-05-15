# swift-kurrentdb

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2Fswift-kurrentdb%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2Fswift-kurrentdb%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift Package Index](https://img.shields.io/badge/Swift%20Package%20Index-available-brightgreen)](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb)
[![Swift-build-testing](https://github.com/gradyzhuo/swift-kurrentdb/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/gradyzhuo/swift-kurrentdb/actions/workflows/swift-build-testing.yml)
[![codecov](https://codecov.io/gh/gradyzhuo/swift-kurrentdb/graph/badge.svg)](https://codecov.io/gh/gradyzhuo/swift-kurrentdb)

<div align=center>
<img src="https://cdn.bsky.app/img/feed_thumbnail/plain/did:plc:fikpipzuggbnuqew3treexnn/bafkreiadjakshxna7sn2gtwxdibew7e66vp3xplpghr72sxpwptsq7gf3i@jpeg" height="200px" width="200px" >

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

```swift
// 2.x — current stable, target-based API
dependencies: [
    .package(url: "https://github.com/gradyzhuo/swift-kurrentdb.git", from: "2.0.3")
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
let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .cerificate(path: "/path/to/ca.crt")

// Production — remote cluster (TLS enabled by default)
let settings = ClientSettings.remote(
    "node1.example.com:2113",
    "node2.example.com:2113",
    "node3.example.com:2113"
).authenticated(.credentials(username: "admin", password: "changeit"))

// Connection string
let settings: ClientSettings = "esdb://admin:changeit@node1:2113,node2:2113?tls=true"

let client = KurrentDBClient(settings: settings)
```

---

### Append and Read Events

```swift
// Create an event
let event = EventData(
    eventType: "OrderPlaced",
    model: ["orderId": "order-123", "total": 99.99]
)

// Append to stream
try await client.appendToStream("orders", events: [event]) {
    $0.revision(expected: .any)
}

// Read events
let responses = try await client.readStream("orders") {
    $0.startFrom(revision: .start).limit(10)
}

for try await response in responses {
    if let event = try response.event {
        print("Event: \(event.record.eventType)")
    }
}
```

---

## API Overview

### Streams

```swift
// Append
try await client.appendToStream("orders", events: [event]) {
    $0.revision(expected: .streamExists)
}

// Read forward
let responses = try await client.readStream("orders") {
    $0.startFrom(revision: .start).limit(50)
}

// Read backward
let responses = try await client.readStream("orders") {
    $0.startFrom(revision: .end).limit(10).backward()
}

// Read $all
let allResponses = try await client.readAllStreams {
    $0.limit(100)
}

// Subscribe (catch-up)
let subscription = try await client.subscribeStream("orders")
for try await event in subscription.events { ... }

// Subscribe to $all
let subscription = try await client.subscribeAllStreams()

// Delete / tombstone
try await client.deleteStream("orders")
try await client.tombstoneStream("orders")

// Stream metadata
try await client.setStreamMetadata("orders", metadata: metadata)
let metadata = try await client.getStreamMetadata("orders")
```

### Projections

```swift
// Create
try await client.createContinuousProjection(name: "order-count", query: js)
try await client.createOneTimeProjection(query: js)
try await client.createTransientProjection(name: "temp", query: js)

// Lifecycle
try await client.enableProjection(name: "order-count")
try await client.disableProjection(name: "order-count")
try await client.abortProjection(name: "order-count")
try await client.resetProjection(name: "order-count")
try await client.deleteProjection(name: "order-count")

// Query state / result
let state: CountResult? = try await client.getProjectionState(of: CountResult.self, name: "order-count")
let result: Int? = try await client.getProjectionResult(of: Int.self, name: "order-count")

// List
let continuous = try await client.listAllProjections(mode: .continuous)
let all = try await client.listAllProjections(mode: .any)
```

### Persistent Subscriptions

```swift
// Create a subscription group
try await client.createPersistentSubscription(
    stream: "orders",
    groupName: "order-workers"
) {
    $0.startFrom(revision: .start)
      .maxRetryCount(5)
}

// Subscribe and process events
let subscription = try await client.subscribePersistentSubscription(
    stream: "orders",
    groupName: "order-workers"
)

for try await result in subscription.events {
    do {
        // handle event
        try await subscription.ack(readEvents: result.event)
    } catch {
        try await subscription.nack(readEvents: result.event, action: .park, reason: "\(error)")
    }
}

// $all persistent subscription
try await client.createPersistentSubscriptionToAllStream(groupName: "all-workers")
let allSub = try await client.subscribePersistentSubscriptionToAllStreams(groupName: "all-workers")

// Update / delete
try await client.updatePersistentSubscription(stream: "orders", groupName: "order-workers") { $0 }
try await client.deletePersistentSubscription(stream: "orders", groupName: "order-workers")
```

### User Management

```swift
// Create a user
try await client.createUser(
    loginName: "jane",
    password: "secure_password",
    fullName: "Jane Doe",
    groups: ["ops"]
)

// Manage user
try await client.enableUser(loginName: "jane")
try await client.disableUser(loginName: "jane")
try await client.changeUserPassword(loginName: "jane", currentPassword: "old", newPassword: "new")
try await client.resetUserPassword(loginName: "jane", newPassword: "reset")
```

### Server Operations

```swift
// Scavenge
let response = try await client.startScavenge(threadCount: 2, startFromChunk: 0)
try await client.stopScavenge(scavengeId: response.scavengeId)

// System
try await client.mergeIndexes()
try await client.restartPersistentSubscriptions()

// Node
try await client.resignNode()
try await client.setNodePriority(priority: 10)
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

```swift
// 1.x
try await client.appendToStream("orders", events: [event]) { ... }

// 2.x
try await client.streams(of: .specified("orders")).append(events: [event]) { ... }
```

### The 1.x API moves to `KurrentDB_V1`

In 2.x the old flat-method API is **no longer part of the `KurrentDB` module**.
It has been moved to a separate `KurrentDB_V1` library that ships in the same package.
If you are not ready to migrate immediately, switch your dependency target and import:

```swift
// Package.swift
.product(name: "KurrentDB_V1", package: "swift-kurrentdb")
```

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
| **Streams** | Append, read, delete, subscribe (catch-up), $all stream |
| **Persistent Subscriptions** | Create, subscribe, update, delete, ACK/NAK, $all support |
| **Projections** | Create (continuous/one-time/transient), enable, disable, state, result |
| **Users** | Create, enable, disable, update, change/reset password |
| **Operations** | Scavenge (start/stop), merge indexes, shutdown, node priority |
| **Gossip** | Cluster discovery, node health, leader detection |
| **Monitoring** | Real-time server statistics |
| **Connection** | TLS/SSL, cluster gossip discovery, auto-reconnection, keep-alive |

## Test Coverage

**75% line coverage** across the `KurrentDB` module, measured by running all 174 tests against a live 3-node TLS KurrentDB cluster.

### Coverage by Subsystem

| Subsystem | Line Coverage | Lines |
|-----------|:------------:|------:|
| Monitoring | 88.4% | 95 |
| ServerFeatures | 90.2% | 61 |
| Users | 87.6% | 403 |
| Streams | 86.1% | 1,560 |
| Operations | 83.0% | 235 |
| Projections | 77.3% | 865 |
| PersistentSubscriptions | 71.9% | 1,555 |
| Gossip | 66.9% | 142 |
| Core | 66.8% | 2,650 |
| **KurrentDB (total)** | **75.0%** | **7,581** |

### Test Suites

174 tests across 9 integration suites and 2 unit/mock suites. All integration tests run against a live 3-node TLS KurrentDB cluster.

| Suite | Tests | Type | Key Scenarios |
|-------|------:|------|---------------|
| **StreamsTests** | 35 | Integration | Append, read (forward/backward/limit/revision), subscribe, metadata, optimistic concurrency, delete, tombstone |
| **ProjectionsTests** | 16 | Integration | Create (continuous/one-time/transient), enable/disable, abort, reset, state/result query, list |
| **PersistentSubscriptionsTests** | 11 | Integration | Create, subscribe, ACK, NACK (park/retry), getInfo, update settings, list, delete, replay parked |
| **UsersTests** | 7 | Integration | Create, enable/disable, update, change/reset password |
| **OperationsTests** | 6 | Integration | Scavenge (start/stop), merge indexes, restart persistent subscriptions, node priority, resign |
| **GossipTests** | 3 | Integration | Read cluster members, node state, custom timeout |
| **MonitoringTests** | 3 | Integration | Server stats, refresh interval, metadata flag |
| **KurrentCoreTests** | 67 | Unit | Connection string parsing, `EventData`, projection status, stream identifiers, metadata, subscription filters |
| **MockClientTests** | 26 | Mock/DI | `KurrentDBClientProtocol` conformance, all factory call patterns, 5 domain service scenarios |
| **Total** | **174** | | 0 commented-out tests |

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

## Requirements

- Swift 6.0+
- macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+ / Linux

### KurrentDB Server Compatibility

| Server Version | Status | Notes |
|:--------------:|:------:|-------|
| **KurrentDB 26.0** | ✅ Supported | Full feature support |
| **KurrentDB 25.1** | ✅ Supported | Full feature support |
| **EventStoreDB 24.x** | ✅ Supported | Core features supported; KurrentDB v2 batch append not available |

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
| [Appending Events](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/appending-events) | EventData, concurrency control, idempotency |
| [Reading Events](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/reading-events) | Forward/backward reading, $all stream, filters |
| [Projections](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/projections) | Create, manage, and query projection state |
| [Persistent Subscriptions](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/persistent-subscriptions) | Competing consumers, ACK/NAK, subscription groups |
| [User Management](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/user-management) | Create, enable, disable, password management |
| [Cluster Gossip](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/cluster-gossip) | Cluster discovery, node health monitoring |
| [Monitoring](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/monitoring) | Real-time server statistics |
| [Server Operations](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb/server-operations) | Scavenge, index merge, shutdown, node management |
| [Full API Reference](https://swiftpackageindex.com/gradyzhuo/swift-kurrentdb/documentation/kurrentdb) | Complete API documentation |

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, documentation improvements, or code contributions.

- [GitHub Discussions](https://github.com/gradyzhuo/swift-kurrentdb/discussions) — Ask questions, share ideas
- [Issues](https://github.com/gradyzhuo/swift-kurrentdb/issues) — Report bugs
- [Contributing Guide](CONTRIBUTING.md) — Get started contributing

## License

MIT License — see [LICENSE](Licence) for details.

## Acknowledgments

Built with:
- [grpc-swift](https://github.com/grpc/grpc-swift) — Swift gRPC implementation (v2.x)
- [swift-nio](https://github.com/apple/swift-nio) — Non-blocking I/O
- [swift-log](https://github.com/apple/swift-log) — Logging API

### Design influences and divergences

The shape of the public API and the underlying wire semantics owe a lot to the official
Kurrent/EventStoreDB clients — primarily the [.NET](https://github.com/EventStore/EventStore-Client-Dotnet),
[Java](https://github.com/EventStore/EventStoreDB-Client-Java), and
[Node.js](https://github.com/EventStore/EventStoreDB-Client-NodeJS) clients.
What was adopted, and where this client deliberately takes a different path:

**Adopted from the official clients**
- The `esdb://` connection string format, cluster gossip discovery, and `NodePreference`
  semantics (leader / follower / random) for routing.
- Optimistic concurrency via expected revision (`.any` / `.noStream` / `.streamExists` / `.at(n)`)
  and the resulting `wrongExpectedVersion` error path.
- Persistent subscription ACK/NACK with park/retry/skip/stop semantics.
- Subscription filtering primitives (event-type / stream-name prefix and regex).

**Where swift-kurrentdb diverges**
- **Target-based API instead of flat methods.** Official clients expose a flat surface like
  `client.appendToStream(name, options, events)`. swift-kurrentdb scopes operations through
  typed targets — `client.streams(of: .specified("orders")).append(...)`,
  `client.projections(name: ...)`, `client.persistentSubscriptions(stream: ..., group: ...)` —
  so the compiler rules out illegal operations (e.g. tombstoning `$all`) before they reach the wire.
- **Trailing-closure builders for options** instead of options objects/records. This keeps the
  call site terse and removes the need for either parameter overloads or partially-filled structs.
- **Actor-based client with Swift 6 strict concurrency.** `KurrentDBClient` and `NodeSelector`
  are actors, not thread-safe instances guarded by locks. The whole package compiles under
  `-strict-concurrency=complete` with zero `@unchecked Sendable`.
- **Typed throws.** Operations throw `KurrentError` rather than a hierarchy of untyped
  exceptions, so callers exhaustively handle failure cases at compile time.
- **Three-layer module split** (`KurrentDB` → `GRPCEncapsulates` → `Generated`).
  gRPC patterns (`UnaryUnary`, `UnaryStream`, etc.) live in their own module so the public
  API stays decoupled from generated protobuf types — the same pattern can be reused by
  other gRPC-backed Swift clients without dragging KurrentDB-specific types along.

---

Made by [Grady Zhuo](https://github.com/gradyzhuo)
