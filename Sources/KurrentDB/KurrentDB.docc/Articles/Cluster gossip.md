# Cluster gossip

Query cluster topology via the gossip protocol to discover nodes, monitor health, and understand the current state of your KurrentDB cluster.

## Overview

The gossip protocol is the mechanism KurrentDB uses internally for cluster node discovery. By querying gossip, you can discover all nodes in the cluster, their roles (leader, follower, read-only replica), and their health status — all from a single endpoint.

This is especially useful when you only know one node's address and need to discover the rest of the cluster, or when building monitoring and health-check systems.

## Creating a client

Gossip operations work with any valid client configuration — standalone, DNS, or seed-based.

```swift
let settings: ClientSettings = .localhost()
let client = KurrentDBClient(settings: settings)
```

## Read cluster members

The `readGossip()` method queries the cluster endpoints configured in your client settings and returns information about all known cluster members.

```swift
let members = try await client.readGossip()

for member in members {
    print("Node \(member.instanceId): \(member.state), alive: \(member.isAlive)")
    print("  Endpoint: \(member.httpEndPoint.host):\(member.httpEndPoint.port)")
}
```

### How it works

The gossip query is sent directly to the cluster endpoints defined in your ``ClientSettings/clusterMode``:

| Cluster Mode | Behavior |
|-------------|----------|
| `.standalone(endpoint)` | Queries the single endpoint |
| `.dns(endpoint)` | Queries the DNS endpoint |
| `.seeds([endpoints])` | Tries each seed endpoint until one responds |

When using seed-based discovery, the client iterates through each candidate endpoint. As soon as one responds with a non-empty member list, that result is returned. This means you can **discover the entire cluster topology by querying any single node**.

```swift
// Connect to just one known node
let settings: ClientSettings = .init(clusterMode: .seeds([
    .init(host: "node1.example.com", port: 2113)
]))
let client = KurrentDBClient(settings: settings)

// Discover ALL nodes in the cluster from that single endpoint
let members = try await client.readGossip()
print("Discovered \(members.count) nodes in the cluster")

for member in members {
    print("  \(member.httpEndPoint.host):\(member.httpEndPoint.port) — \(member.state)")
}
```

### Custom timeout

You can specify a custom timeout for the gossip query. If not provided, the client's configured gossip timeout is used.

```swift
let members = try await client.readGossip(timeout: .seconds(5))
```

## Find the leader node

A common use case is locating the current cluster leader for write operations.

```swift
let members = try await client.readGossip()

if let leader = members.first(where: { $0.state == .leader && $0.isAlive }) {
    print("Leader: \(leader.httpEndPoint.host):\(leader.httpEndPoint.port)")
}
```

## Monitor cluster health

Use gossip to build health checks or monitoring dashboards.

```swift
let members = try await client.readGossip()

let alive = members.filter(\.isAlive)
let dead = members.filter { !$0.isAlive }

print("Cluster: \(alive.count) alive, \(dead.count) unreachable")

for member in dead {
    print("  Unreachable: \(member.httpEndPoint.host):\(member.httpEndPoint.port)")
}
```

## Node states

Each cluster member has a ``Gossip/VNodeState`` indicating its current role:

| State | Description |
|-------|-------------|
| `.leader` | Accepts reads and writes; elected by the cluster |
| `.follower` | Replicates from the leader; can serve reads |
| `.readOnlyReplica` | Read-only node that replicates data |
| `.clone` | Node is cloning data from another node |
| `.catchingUp` | Node is catching up to the current state |
| `.manager` | Cluster manager node (non-data) |
| `.initializing` | Node is starting up |
| `.shuttingDown` | Node is in the process of shutting down |
| `.shutdown` | Node has completed shutdown |
| `.resigningLeader` | Leader is stepping down for a new election |
| `.discoverLeader` | Node is discovering the current leader |
| `.preReplica` | Node is preparing to become a replica |
| `.preLeader` | Node is preparing to become the leader |
| `.preReadOnlyReplica` | Node is preparing to become a read-only replica |
| `.readOnlyLeaderless` | Read-only node with no known leader |

## Member information

Each ``Gossip/MemberInfo`` contains:

| Property | Type | Description |
|----------|------|-------------|
| `instanceId` | `UUID` | Unique identifier for the node |
| `state` | ``Gossip/VNodeState`` | Current node state |
| `isAlive` | `Bool` | Whether the node is currently responsive |
| `httpEndPoint` | ``Endpoint`` | The node's host and port for client connections |
| `timeStamp` | `TimeInterval` | Timestamp of the gossip information |
