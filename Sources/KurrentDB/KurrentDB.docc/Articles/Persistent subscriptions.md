# Persistent subscriptions

Manage persistent subscription groups for competing consumers: reliable, distributed event processing with server-side retries and checkpoints.

## Creating a client

Managing persistent subscriptions needs credentials with the right permissions:

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

For TLS, clusters and remote servers, see <doc:Getting-started>.

## Overview

Persistent subscriptions follow the **competing consumers** model: several clients connect to the same subscription group, and the server distributes the events among them. The server tracks the group's position, retries events that fail, and delivers every event at least once.

- Each event goes to one consumer in the group, chosen by the group's consumer strategy.
- The server stores the group's checkpoint.
- Events pending on a consumer that disconnects are redelivered to the others.

## Subscription lifecycle

1. **Create** the subscription group and its settings.
2. **Subscribe** consumers to receive events.
3. **Process** each event and acknowledge it (ack) or reject it (nack).
4. **Update** the settings, keeping the checkpoint (optional).
5. **Delete** the group when it's no longer needed.

## Choosing a target

Every operation starts from a ``PersistentSubscriptions`` value for a target:

| Accessor | Target | Operations |
|----------|--------|------------|
| `client.persistentSubscriptions(stream:group:)` | One stream + group | `create`, `update`, `delete`, `subscribe`, `getInfo`, `replayParked` |
| `client.persistentSubscriptions(filterGroup:)` | `$all` + group | `create`, `update`, `delete`, `subscribe`, `getInfo`, `replayParked` |
| `client.persistentSubscriptions(filterStream:)` | All groups on one stream | `list` |
| `client.allPersistentSubscriptions` | Every group on the server | `list`, `restartSubsystem` |

## Create a subscription

### On a specific stream

```swift
try await client.persistentSubscriptions(stream: "order-events", group: "order-processing-workers")
    .create {
        $0.revision = .start
        $0.settings.messageTimeout = .ms(30_000)
        $0.settings.maxRetryCount = 5
        $0.settings.checkpointAfter = .ms(10_000)
    }
```

A new group starts at the **end** of the stream unless you set `revision`.

### On the $all stream

A group on `$all` processes events from every stream — useful for cross-cutting work such as audit logging or analytics. Set `filter` to limit it to the streams or event types you need:

```swift
try await client.persistentSubscriptions(filterGroup: "global-audit-logger")
    .create {
        $0.position = .start
        $0.filter = .onStreamName(prefixes: ["order-", "payment-"])
        $0.settings.messageTimeout = .ms(60_000)
        $0.settings.maxRetryCount = 3
    }
```

> Warning: `$all` groups can see very high event volumes. Use a filter and suitable buffer sizes so consumers aren't overwhelmed.

### Settings

`settings` is a ``PersistentSubscription/CreateSettings`` value. Its defaults match the server's:

| Setting | Default | Meaning |
|---------|---------|---------|
| `messageTimeout` | 30 s | How long the server waits for an ack before retrying |
| `maxRetryCount` | 10 | Retries before an event is parked |
| `checkpointAfter` | 2 s | Minimum time between checkpoints |
| `checkpointCount` | `10...1000` | Minimum and maximum events between checkpoints |
| `liveBufferSize` | 500 | Live events buffered in memory |
| `readBatchSize` | 20 | Events read from disk per batch |
| `historyBufferSize` | 500 | Historical events buffered in memory |
| `maxSubscriberCount` | 0 (unlimited) | Maximum consumers in the group |
| `consumerStrategy` | `.roundRobin` | `.roundRobin`, `.dispatchToSingle`, `.pinned`, `.pinnedByCorrelation` |
| `resolveLink` | `false` | Deliver the linked event for link events |

Durations are ``TimeSpan`` values, such as `.ms(30_000)`.

## Subscribe and process events

### Connecting a consumer

```swift
let subscription = try await client
    .persistentSubscriptions(stream: "order-events", group: "order-processing-workers")
    .subscribe()

for try await result in subscription.events {
    print(result.event.record, "retry count:", result.retryCount)
    try await subscription.ack(readEvents: result.event)
}
```

Set `bufferSize` in the `subscribe` closure to control how many unacknowledged events the server sends ahead.

### Acknowledging events

Acknowledge every event you receive:

| Call | Effect |
|------|--------|
| `ack(readEvents:)` | Processed; the checkpoint can move past it |
| `nack(readEvents:action: .retry, reason:)` | Failed; redeliver it |
| `nack(readEvents:action: .park, reason:)` | Move it to the parked queue for manual handling |
| `nack(readEvents:action: .skip, reason:)` | Drop it without retrying |

<!-- snippet:toplevel -->
```swift
struct RecoverableError: Error {}

func processOrder(_ event: ReadEvent) async throws {
    // Your processing logic.
}
```

```swift
let subscription = try await client
    .persistentSubscriptions(stream: "order-events", group: "order-processing-workers")
    .subscribe()

for try await result in subscription.events {
    do {
        try await processOrder(result.event)
        try await subscription.ack(readEvents: result.event)
    } catch let error as RecoverableError {
        try await subscription.nack(readEvents: result.event, action: .retry, reason: "\(error)")
    } catch {
        try await subscription.nack(readEvents: result.event, action: .park, reason: "\(error)")
    }
}
```

> Warning: An event you neither ack nor nack times out and is retried, which can build a backlog.

### Subscribing to $all

```swift
let subscription = try await client
    .persistentSubscriptions(filterGroup: "global-audit-logger")
    .subscribe()

for try await result in subscription.events {
    try await subscription.ack(readEvents: result.event)
}
```

### Handling a dropped subscription

When the server drops the subscription, iterating `events` throws ``KurrentError/subscriptionDropped(reason:lastRevision:lastPosition:)``. It carries the revision (stream groups) or position (`$all` groups) of the last event you received:

```swift
let subscription = try await client
    .persistentSubscriptions(stream: "order-events", group: "order-processing-workers")
    .subscribe()

do {
    for try await result in subscription.events {
        try await subscription.ack(readEvents: result.event)
    }
} catch let KurrentError.subscriptionDropped(reason, lastRevision, lastPosition) {
    print("Dropped: \(reason), last revision: \(String(describing: lastRevision)), last position: \(String(describing: lastPosition))")
}
```

### Closing a subscription

A subscription's connection closes when nothing references the subscription or its `events` stream any more — for example, when the scope holding them ends. This holds whether or not you iterated `events`.

Breaking out of the `for try await` loop alone doesn't close the connection while you still hold the subscription. Let the references go, or call ``KurrentDBClient/shutdown()``, to end it.

## Update a subscription

Change a group's settings while keeping its checkpoint. Only the settings you set change; ``PersistentSubscription/UpdateSettings`` leaves every `nil` setting as it is.

```swift
try await client.persistentSubscriptions(stream: "order-events", group: "order-processing-workers")
    .update {
        $0.settings.messageTimeout = .ms(120_000)
        $0.settings.maxRetryCount = 10
    }
```

For `$all` groups:

```swift
try await client.persistentSubscriptions(filterGroup: "analytics-processor")
    .update {
        $0.settings.messageTimeout = .ms(90_000)
        $0.settings.checkpointAfter = .ms(60_000)
    }
```

> Note: Connected consumers may be briefly disrupted while the new settings take effect.

## Replay parked events

Parked events stay in the group's parked queue until you replay them:

```swift
try await client.persistentSubscriptions(stream: "order-events", group: "order-processing-workers")
    .replayParked()
```

## Delete a subscription

Deleting a group removes its checkpoint, retry state and parked events.

```swift
try await client.persistentSubscriptions(stream: "order-events", group: "old-order-processor")
    .delete()

try await client.persistentSubscriptions(filterGroup: "legacy-analytics")
    .delete()
```

> Warning: Deletion is permanent.

## Inspect subscriptions

### One group

```swift
let info = try await client
    .persistentSubscriptions(stream: "order-events", group: "order-processing-workers")
    .getInfo()

print(info.groupName, info.status, info.connections.count)
```

### Groups on a stream

```swift
let subscriptions = try await client.persistentSubscriptions(filterStream: "orders").list()

for subscription in subscriptions {
    print("Group: \(subscription.groupName), connections: \(subscription.connections.count)")
}
```

### Every group on the server

```swift
let allSubscriptions = try await client.allPersistentSubscriptions.list()

print("Total subscription groups: \(allSubscriptions.count)")

// Find groups with parked events
for subscription in allSubscriptions where subscription.parkedMessageCount > 0 {
    print("\(subscription.groupName): \(subscription.parkedMessageCount) parked events")
}
```

## Restart the subsystem

Restarting the persistent subscription subsystem reloads every group from its last checkpoint. It affects the whole cluster.

```swift
try await client.allPersistentSubscriptions.restartSubsystem()
```

> Warning: Every connected consumer is disconnected. Use it only in maintenance windows or to recover the subsystem.

## Architecture

For details on the target-based design of the Persistent Subscriptions API, see <doc:PersistentSubscriptionTarget-design>.
