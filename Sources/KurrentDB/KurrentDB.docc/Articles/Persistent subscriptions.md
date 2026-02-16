# Persistent subscriptions

Manage persistent subscription groups for competing consumer patterns, enabling reliable, distributed event processing with automatic retry and checkpoint management.

## Creating a client

Persistent subscription management requires appropriate credentials.

```swift
let settings: ClientSettings = .localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

## Overview

Persistent subscriptions provide a **competing consumer** model where multiple clients can subscribe to the same subscription group and have events distributed among them. The server tracks the group's position in the stream, handles retries for failed events, and provides at-least-once delivery guarantees.

Key characteristics:
- Events are distributed round-robin across connected consumers
- Each event is delivered to exactly one consumer in the group
- The server maintains the group's checkpoint position
- Failed consumers do not lose events; the server redistributes their pending events

## Subscription lifecycle

The typical workflow for persistent subscriptions follows these phases:

1. **Create** — Define the subscription group and configuration
2. **Subscribe** — Connect consumers to receive events
3. **Process** — Handle events and ACK/NAK as needed
4. **Update** — Modify configuration while preserving checkpoint (optional)
5. **Delete** — Remove the subscription group entirely (when no longer needed)

## Create a subscription

### On a specific stream

Creates a persistent subscription group for a specific stream.

```swift
try await client.createPersistentSubscription(
    stream: "order-events",
    groupName: "order-processing-workers"
) {
    $0.startFrom(revision: .start)
      .messageTimeout(seconds: 30)
      .maxRetryCount(5)
      .bufferSize(20)
      .checkpointAfter(seconds: 10)
}
```

### On the $all stream

Creates a subscription group that processes events from every stream in the event store. Useful for cross-cutting concerns like audit logging or analytics.

```swift
try await client.createPersistentSubscriptionToAllStream(
    groupName: "global-audit-logger"
) {
    $0.startFrom(position: .start)
      .messageTimeout(seconds: 60)
      .maxRetryCount(3)
      .checkpointAfter(seconds: 30)
}
```

> Warning: `$all` subscriptions can generate very high event volumes. Configure appropriate filters and buffer sizes to prevent overwhelming consumers.

### Configuration options

| Option | Description |
|--------|-------------|
| Start Position | Where to begin reading (start, end, position/revision) |
| Message Timeout | How long to wait for ACK before retrying |
| Max Retry Count | Number of retries before parking failed events |
| Buffer Size | Number of events to buffer per consumer |
| Strategy | Round-robin, dispatch to single, or pinned consumer |
| Live Buffer Size | In-memory buffer for live events |
| Read Batch Size | Number of events to read from disk per batch |
| Checkpoint Settings | Checkpoint interval and thresholds |

## Subscribe and process events

### Connecting a consumer

```swift
let subscription = try await client.subscribePersistentSubscription(
    stream: "order-events",
    groupName: "order-processing-workers"
)

for try await result in subscription.events {
    // Process the event
    let event = result.event

    // Acknowledge successful processing
    try await subscription.ack(readEvents: event)
}
```

### Acknowledging events

Each event must be acknowledged with one of these actions:

| Action | Description |
|--------|-------------|
| ACK | Event processed successfully, advance checkpoint |
| NAK (retry) | Event processing failed, retry based on subscription settings |
| NAK (park) | Move event to parked queue for manual intervention |
| NAK (skip) | Skip this event without retrying |

```swift
for try await result in subscription.events {
    do {
        try await processOrder(result.event)
        try await subscription.ack(readEvents: result.event)
    } catch let error as RecoverableError {
        // Retry on recoverable errors
        try await subscription.nack(readEvents: result.event, action: .retry, reason: "\(error)")
    } catch {
        // Park on unrecoverable errors for manual review
        try await subscription.nack(readEvents: result.event, action: .park, reason: "\(error)")
    }
}
```

### Subscribing to $all

```swift
let subscription = try await client.subscribePersistentSubscriptionToAllStreams(
    groupName: "global-audit-logger"
)

for try await result in subscription.events {
    try await subscription.ack(readEvents: result.event)
}
```

> Warning: Failing to acknowledge events causes them to time out and retry, potentially creating processing backlogs. Always ACK or NAK every event received.

## Update a subscription

Updates configuration for an existing subscription group while preserving its checkpoint position.

```swift
try await client.updatePersistentSubscription(
    stream: "order-events",
    groupName: "order-processing-workers"
) {
    $0.messageTimeout(seconds: 120)
      .maxRetryCount(10)
      .bufferSize(50)
}
```

For `$all` subscriptions:

```swift
try await client.updatePersistentSubscriptionToAllStream(
    groupName: "analytics-processor"
) {
    $0.messageTimeout(seconds: 90)
      .checkpointAfter(seconds: 60)
}
```

> Note: Connected consumers may experience brief disruption as the new configuration takes effect.

## Delete a subscription

Permanently removes a subscription group, including its checkpoint, retry state, and parked events.

```swift
try await client.deletePersistentSubscription(
    stream: "order-events",
    groupName: "old-order-processor"
)
```

For `$all` subscriptions:

```swift
try await client.deletePersistentSubscriptionToAllStream(
    groupName: "legacy-analytics"
)
```

> Warning: Deletion is permanent and cannot be undone. Checkpoint positions and parked events are lost.

## List subscriptions

### List by stream

```swift
let subscriptions = try await client.listPersistentSubscriptions(stream: "orders")

for sub in subscriptions {
    print("Group: \(sub.groupName)")
    print("Connections: \(sub.connectionCount)")
}
```

### List $all subscriptions

```swift
let allSubscriptions = try await client.listPersistentSubscriptionsToAllStream()

for sub in allSubscriptions {
    print("Global subscription: \(sub.groupName)")
}
```

### List all subscriptions across all streams

```swift
let allSubscriptions = try await client.listAllPersistentSubscription()

print("Total subscription groups: \(allSubscriptions.count)")

// Find subscriptions with parked events
let withParked = allSubscriptions.filter { $0.parkedMessageCount > 0 }
for sub in withParked {
    print("\(sub.groupName): \(sub.parkedMessageCount) parked events")
}
```

## Restart the subsystem

Restarts the entire persistent subscription subsystem, reinitializing all subscription groups from their last checkpoints. This is a cluster-wide disruptive operation.

```swift
try await client.restartPersistentSubscriptionSubsystem()
```

> Warning: All connected consumers will be disconnected. Only use during maintenance windows or when recovering from subsystem failures.

## Target-based API

Persistent subscriptions use a target-based API accessed through the ``Streams`` interface. The ``PersistentSubscriptionTarget`` protocol provides type-safe access to different subscription scopes.

### Available targets

| Target | Scope | Operations |
|--------|-------|------------|
| `PersistentSubscription.Specified` | Specific stream + group | `create()`, `update()`, `delete()`, `subscribe()`, `getInfo()`, `replayParked()` |
| `PersistentSubscription.AllStream` | `$all` stream + group | `create()`, `update()`, `delete()`, `subscribe()`, `getInfo()`, `replayParked()` |
| `PersistentSubscription.All` | Cluster-wide | `list(for:)`, `restartSubsystem()` |

### Using the target API directly

```swift
// Via Streams — specific stream
let ps = client.streams(of: .specified("orders"))
    .persistentSubscriptions(group: "order-workers")

try await ps.create()
let subscription = try await ps.subscribe()
try await ps.delete()

// Via Streams — $all stream
let allPs = client.streams(of: .all)
    .persistentSubscriptions(group: "audit-logger")

try await allPs.create()
let allSubscription = try await allPs.subscribe()
```

## Architecture

For details on the target-based design of the Persistent Subscriptions API, see <doc:PersistentSubscriptionTarget-design>.
