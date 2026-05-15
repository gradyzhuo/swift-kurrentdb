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
try await client.streams(specified: "orders").append(events: [event]) {
    $0.expectedRevision = .any
}

// Read events
let responses = try await client.streams(specified: "orders").read {
    $0.revision = .start
    $0.limit = 10
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
try await client.streams(specified: "orders").append(events: [event]) {
    $0.expectedRevision = .streamExists
}

// Read forward
let responses = try await client.streams(specified: "orders").read {
    $0.revision = .start
    $0.limit = 50
}

// Read backward
let responses = try await client.streams(specified: "orders").read {
    $0.revision = .end
    $0.direction = .backward
    $0.limit = 10
}

// Read $all
let allResponses = try await client.allStreams.read {
    $0.limit = 100
}

// Subscribe (catch-up)
let subscription = try await client.streams(specified: "orders").subscribe()
for try await event in subscription.events { ... }

// Subscribe to $all
let subscription = try await client.allStreams.subscribe()

// Delete / tombstone
try await client.streams(specified: "orders").delete()
try await client.streams(specified: "orders").tombstone()

// Stream metadata
try await client.streams(specified: "orders").setMetadata(metadata: metadata)
let metadata = try await client.streams(specified: "orders").getMetadata()
```

### Projections

```swift
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
| **KurrentDB 26.1** | ✅ Supported | Full feature support |
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

---

Made by [Grady Zhuo](https://github.com/gradyzhuo)
