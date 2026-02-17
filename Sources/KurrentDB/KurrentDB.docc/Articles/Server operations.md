# Server operations

Perform administrative and maintenance tasks on your KurrentDB cluster, including scavenging, index merging, shutdowns, and node management.

## Creating a client

Server operations require administrative or operational credentials. Users must belong to the `.admins` or `.ops` group.

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

For TLS-enabled or multi-node clusters:

```swift
// Multi-node localhost with TLS
let settings = ClientSettings.localhost(ports: 2111, 2112, 2113)
    .secure(true)
    .tlsVerifyCert(false)
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .cerificate(path: "/path/to/ca.crt")
let client = KurrentDBClient(settings: settings)

// Remote cluster (secure: true by default)
let settings = ClientSettings.remote(
    "node1.example.com:2113",
    "node2.example.com:2113",
    "node3.example.com:2113"
).authenticated(.credentials(username: "admin", password: "changeit"))
  .cerificate(path: "/path/to/ca.crt")
let client = KurrentDBClient(settings: settings)

// Remote without TLS
let settings = ClientSettings.remote(
    "node1.example.com:2113", secure: false
).authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

## Scavenge

Scavenging is a background maintenance operation that physically removes deleted events from database chunks, reclaiming disk space and improving read performance.

### Start a scavenge

```swift
let response = try await client.operations(of: .scavenge)
    .startScavenge(threadCount: 2, startFromChunk: 0)

print("Scavenge started with ID: \(response.scavengeId)")
```

The `threadCount` parameter controls parallelism:

| Value | Trade-off |
|-------|-----------|
| 1 | Minimal impact on normal operations, slower completion |
| 2–4 | Recommended for production systems |
| Higher | Faster completion but higher CPU/disk I/O usage |

The `startFromChunk` parameter allows resuming interrupted scavenges. Use `0` to start from the beginning.

### Stop a scavenge

Stops a running scavenge gracefully. The current chunk completes before halting, and the position is saved for potential resumption.

```swift
try await client.operations(of: .activeScavenge(scavengeId: response.scavengeId))
    .stopScavenge()
```

### Start and stop workflow

```swift
// Start a scavenge
let response = try await client.operations(of: .scavenge)
    .startScavenge(threadCount: 2, startFromChunk: 0)

let scavengeId = response.scavengeId

// Later, stop if needed
let stopResponse = try await client.operations(of: .activeScavenge(scavengeId: scavengeId))
    .stopScavenge()
print("Scavenge stopped. Result: \(stopResponse.result)")

// Resume later from where it stopped
try await client.operations(of: .scavenge)
    .startScavenge(threadCount: 2, startFromChunk: lastCompletedChunk)
```

> Warning: Scavenges can be resource-intensive. Schedule them during maintenance windows or low-traffic periods. Do not restart the server while a scavenge is running.

## System operations

### Merge indexes

Consolidates database index segments, reducing disk I/O and improving query performance.

```swift
try await client.operations(of: .system).mergeIndexes()
```

### Restart persistent subscriptions

Stops all persistent subscriptions, clears in-memory state, and reinitializes the subscription manager. All subscription groups reload from persistent storage.

```swift
try await client.operations(of: .system).restartPersistentSubscriptions()
```

### Shutdown

Initiates a graceful shutdown of the KurrentDB server, completing in-flight operations and persisting state before terminating.

```swift
try await client.operations(of: .system).shutdown()
```

> Warning: This operation terminates the server. Ensure all clients are prepared for disconnection before calling this method.

## Node operations

### Resign node

If the node is a leader, it steps down and triggers a new leader election. Useful for graceful maintenance or cluster rebalancing.

```swift
try await client.operations(of: .node).resignNode()
```

### Set node priority

Higher priority nodes are more likely to be elected as leader. Use this to influence cluster leadership distribution.

```swift
try await client.operations(of: .node).setNodePriority(priority: 10)
```

## Architecture

For details on the target-based design of the Operations API, see <doc:OperationsTarget-design>.
