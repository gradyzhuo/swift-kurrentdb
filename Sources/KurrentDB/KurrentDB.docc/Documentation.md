# ``KurrentDB``

@Options(scope: local) {
    @TopicsVisualStyle(hidden)
}

The Kurrent Database Client SDK connected by `gRPC`.

## Articles
- <doc:Migration-guide>
- <doc:Getting-started>
- <doc:Appending-events>
- <doc:Reading-events>
- <doc:Projections>
- <doc:User-management>
- <doc:Persistent-subscriptions>
- <doc:Cluster-gossip>
- <doc:Monitoring>
- <doc:Server-operations>

## Architecture
- <doc:StreamsTarget-design>
- <doc:ProjectionsTarget-design>
- <doc:PersistentSubscriptionTarget-design>
- <doc:UsersTarget-design>
- <doc:OperationsTarget-design>

## Usage

Create a ``KurrentDBClient`` instance with client settings and the number of threads.
Then, interact with a specific stream by creating a `Streams` client for it.

### Streams
```swift
let clientSettings: ClientSettings = "kurrent://localhost:2113?tls=false" // Initialize with actual settings
let client = KurrentDBClient(settings: clientSettings, numberOfThreads: 2)

// Perform an action like appending events to the stream through a typed target
try await client.streams(specified: "streamName").append(events: eventData)

```

### PersistentSubscriptions

```swift
// Import packages of EventStoreDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let client = KurrentDBClient(settings: settings)

// the stream identifier to subscribe.
let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

// the group of subscription
let groupName = "myGroupTest"

let streamName = UUID().uuidString

// Create and subscribe through the typed persistent-subscription target
let persistentSubscriptions = client.persistentSubscriptions(stream: streamName, group: groupName)
try await persistentSubscriptions.create()

let subscription = try await persistentSubscriptions.subscribe()

// Loop all results by subscription.events
for try await result in subscription.events {
    //handle result
    // ...
    
    // ack the readEvent if succeed
    try await subscription.ack(readEvents: result.event)
    // else nack thr readEvent if not succeed.
    // try await subscription.nack(readEvents: result.event, action: .park, reason: "It's failed.")
}

```

## New in 2.1

### AppendRecords — Dynamic Consistency Boundary

Atomically append across multiple streams with cross-stream consistency checks.
Requires server support (KurrentDB 25.1+).

```swift
try await client.multiStreams.appendRecords(
    events: [
        StreamEvent(stream: "order-1", records: [record]),
        StreamEvent(stream: "inventory-1", records: [record]),
    ],
    checks: [.streamState("order-1", .streamExists)]
)
```

### BatchAppend

High-throughput pipelined multi-stream append (v1 `BatchAppend`). Non-atomic —
each item reports its own result.

```swift
let response = try await client.multiStreams.batchAppend(events: [
    StreamEvent(stream: "orders", records: [record]),
    StreamEvent(stream: "audit", records: [record]),
])
```

### Server-side `$all` filtering

Filter `$all` reads on the server by stream name or event type (prefix or regex).

```swift
let events = try await client.allStreams.read {
    $0.filter = .onEventType(prefixes: "OrderPlaced")
}
```

### Per-call credentials & Bearer authentication

Override authentication for a single operation — for multi-tenant or per-request
authorization.

```swift
try await client.streams(specified: "orders")
    .authenticated(.credentials(username: "svc", password: "secret"))
    .append(events: [event])
```

### StreamFilter

``StreamFilter`` (renamed from `SubscriptionFilter`, which is now deprecated) is the
shared filter type for both persistent subscriptions and filtered `$all` reads. Build
it with ``StreamFilter/onStreamName(prefixes:)`` or ``StreamFilter/onEventType(prefixes:)``.


