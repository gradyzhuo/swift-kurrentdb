# KurrentDB-Swift

[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FKurrentDB-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FKurrentDB-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Swift Package Index](https://img.shields.io/badge/Swift%20Package%20Index-available-brightgreen)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![Swift-build-testing](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/offsky-studio/KurrentDB-Swift/actions/workflows/swift-build-testing.yml)

<div align=center>
<img src="assets/kurrent-swift-icon.png" height="200px" width="200px" >

**A modern, type-safe Swift client for Kurrent (formerly EventStoreDB)**

Built for Server-Side Swift and Event Sourcing

[Documentation](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift/documentation/kurrentdb) | [Getting Started](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/getting-started) | [Discussions](https://github.com/gradyzhuo/KurrentDB-Swift/discussions)

</div>

---

## Why KurrentDB-Swift?

Event Sourcing is a powerful pattern for building scalable, auditable systems. KurrentDB-Swift brings this capability to the Swift ecosystem with a modern, type-safe client.

- **Native Swift** — Designed for Swift from the ground up, not a wrapper
- **Modern Concurrency** — Full async/await with Swift 6 data-race safety
- **Type-Safe** — Target-based API design with compile-time guarantees
- **Cluster-Ready** — First-class support for multi-node TLS clusters
- **Well-Documented** — Comprehensive guides on [Swift Package Index](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift/documentation/kurrentdb)
- **Typed Errors** — All operations throw `KurrentError` for precise error handling

## Quick Start

### Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gradyzhuo/KurrentDB-Swift.git", from: "2.0.0-beta.0")
]
```

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

// Production — remote without TLS
let settings = ClientSettings.remote("db.example.com:2113", secure: false)

// Connection string
let settings: ClientSettings = "esdb://admin:changeit@node1:2113,node2:2113?tls=true"

let client = KurrentDBClient(settings: settings)
```

### Append and Read Events

```swift
// Create an event
let event = EventData(
    eventType: "OrderPlaced",
    model: ["orderId": "order-123", "total": 99.99]
)

// Append to stream
try await client.appendStream("orders", events: [event]) {
    $0.revision(expected: .any)
}

// Read events
let events = try await client.readStream("orders") {
    $0.startFrom(revision: .start)
}

for try await response in events {
    if let event = try response.event {
        print("Event: \(event.record.eventType)")
    }
}
```

### Target-Based API

KurrentDB-Swift 2.0 introduces a target-based API design that provides compile-time type safety. Each resource scope exposes only the operations relevant to that target.

#### Streams

```swift
// Specific stream
let stream = client.streams(of: .specified("orders"))

// $all stream
let allStreams = client.streams(of: .all)

// Projection streams
let byEventType = client.streams(of: .byEventType("OrderPlaced"))
let byCategory = client.streams(of: .byStream(prefix: "order"))
```

#### Projections

```swift
// Create a continuous projection
try await client.createContinuousProjection(name: "order-count", query: js)

// Control projections
try await client.enableProjection(name: "order-count")
try await client.disableProjection(name: "order-count")

// Get projection state
let state = try await client.getProjectionState(of: CountResult.self, name: "order-count")
```

#### Persistent Subscriptions

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
    try await subscription.ack(readEvents: result.event)
}
```

#### User Management

```swift
// Create a user
try await client.users.create(
    loginName: "jane",
    password: "secure_password",
    fullName: "Jane Doe",
    groups: [.ops, .custom("order-writers")]
)

// Control a specific user
try await client.user("jane").enable()
try await client.user("jane").disable()
try await client.user("jane").reset(password: "new_password")
```

#### Server Operations

```swift
// Scavenge
let response = try await client.startScavenge(threadCount: 2, startFromChunk: 0)
try await client.stopScavenge(scavengeId: response.scavengeId)

// System
try await client.mergeIndexes()
try await client.shutdown()

// Node
try await client.resignNode()
try await client.setNodePriority(priority: 10)
```

#### Cluster Gossip

```swift
// Discover all nodes from a single endpoint
let members = try await client.readGossip()

for member in members {
    print("\(member.httpEndPoint.host):\(member.httpEndPoint.port) — \(member.state)")
}

// Find the leader
if let leader = members.first(where: { $0.state == .leader && $0.isAlive }) {
    print("Leader: \(leader.httpEndPoint)")
}
```

#### Monitoring

```swift
// Stream server statistics
let stats = try await client.stats(refreshTimePeriodInMs: 5000)

for try await snapshot in stats {
    print("Metrics: \(snapshot.stats.count) entries")
}
```

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

## Requirements

- Swift 6.0+
- macOS 15+ / iOS 18+ / tvOS 18+ / watchOS 11+ / visionOS 2+ / Linux
- Kurrent 24.2+ (or EventStoreDB 23.10+)

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
| [Getting Started](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/getting-started) | Connection settings, first event, basic usage |
| [Appending Events](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/appending-events) | EventData, concurrency control, idempotency |
| [Reading Events](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/reading-events) | Forward/backward reading, $all stream, filters |
| [Projections](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/projections) | Create, manage, and query projection state |
| [Persistent Subscriptions](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/persistent-subscriptions) | Competing consumers, ACK/NAK, subscription groups |
| [User Management](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/user-management) | Create, enable, disable, password management |
| [Cluster Gossip](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/cluster-gossip) | Cluster discovery, node health monitoring |
| [Monitoring](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/monitoring) | Real-time server statistics |
| [Server Operations](https://swiftpackageindex.com/gradyzhuo/kurrentdb-swift/documentation/kurrentdb/server-operations) | Scavenge, index merge, shutdown, node management |
| [Full API Reference](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift/documentation/kurrentdb) | Complete API documentation |

## Contributing

Contributions are welcome! Whether it's bug reports, feature requests, documentation improvements, or code contributions.

- [GitHub Discussions](https://github.com/gradyzhuo/KurrentDB-Swift/discussions) — Ask questions, share ideas
- [Issues](https://github.com/gradyzhuo/KurrentDB-Swift/issues) — Report bugs
- [Contributing Guide](CONTRIBUTING.md) — Get started contributing

## License

MIT License — see [LICENSE](Licence) for details.

## Acknowledgments

Built with:
- [grpc-swift](https://github.com/grpc/grpc-swift) — Swift gRPC implementation
- [swift-nio](https://github.com/apple/swift-nio) — Non-blocking I/O

Inspired by official Kurrent/EventStoreDB clients.

---

Made by [Grady Zhuo](https://github.com/gradyzhuo)
