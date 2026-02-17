# Monitoring

Retrieve real-time server statistics from your KurrentDB cluster for health monitoring, performance analysis, and operational dashboards.

## Overview

The monitoring API provides access to runtime statistics from KurrentDB nodes, including disk usage, memory consumption, queue lengths, and other system metrics. Statistics are delivered as a continuous stream that refreshes at a configurable interval.

## Creating a client

Monitoring operations work with any valid client configuration.

```swift
let settings: ClientSettings = .localhost()
let client = KurrentDBClient(settings: settings)
```

## Retrieve server statistics

The `stats()` method returns an asynchronous stream of stat snapshots. Each snapshot is a dictionary of key-value pairs representing current server metrics.

```swift
let stats = try await client.stats()

for try await snapshot in stats {
    for (key, value) in snapshot.stats {
        print("\(key): \(value)")
    }
}
```

### Refresh interval

By default, statistics refresh every 10 seconds. You can customize the refresh interval:

```swift
// Refresh every 5 seconds
let stats = try await client.stats(refreshTimePeriodInMs: 5000)

for try await snapshot in stats {
    print("Stats updated with \(snapshot.stats.count) metrics")
}
```

### Including metadata

Set `useMetadata` to `true` to include additional metadata in the response:

```swift
let stats = try await client.stats(useMetadata: true)

for try await snapshot in stats {
    for (key, value) in snapshot.stats {
        print("\(key): \(value)")
    }
}
```

## Common metrics

Server statistics include key-value pairs covering various aspects of the node. Common metrics include:

| Category | Examples |
|----------|---------|
| System | CPU usage, memory (free, total), threads |
| Disk | Disk usage, read/write bytes, chunk count |
| Queues | Queue lengths, processing rates |
| Network | Connections, bytes sent/received |
| Event Store | Events appended, read rates, cache hit ratios |

## Reading a single snapshot

If you only need a one-time check rather than continuous monitoring, take the first snapshot from the stream:

```swift
let stats = try await client.stats()

if let snapshot = try await stats.first(where: { _ in true }) {
    if let diskUsage = snapshot.stats["sys-freeMem"] {
        print("Free memory: \(diskUsage)")
    }
}
```

## Building a health check

Use monitoring stats to build simple health checks for your cluster:

```swift
func healthCheck(client: KurrentDBClient) async throws -> Bool {
    let stats = try await client.stats()

    guard let snapshot = try await stats.first(where: { _ in true }) else {
        return false
    }

    // Check that the node is reporting stats
    return !snapshot.stats.isEmpty
}
```

## Combining with gossip

For a comprehensive cluster overview, combine monitoring stats with gossip data:

```swift
// Get cluster topology
let members = try await client.readGossip()
let aliveCount = members.filter(\.isAlive).count
let leader = members.first(where: { $0.state == .leader })

print("Cluster: \(aliveCount)/\(members.count) nodes alive")
if let leader {
    print("Leader: \(leader.httpEndPoint.host):\(leader.httpEndPoint.port)")
}

// Get node stats
let stats = try await client.stats()
if let snapshot = try await stats.first(where: { _ in true }) {
    print("Metrics: \(snapshot.stats.count) entries")
}
```
