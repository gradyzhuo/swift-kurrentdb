# ``KurrentDB``

@Options(scope: local) {
    @TopicsVisualStyle(hidden)
}

A modern, type-safe Swift client for KurrentDB (formerly EventStoreDB), built on gRPC and Swift Concurrency.

## Articles
- <doc:Getting-started>
- <doc:Appending-events>
- <doc:Reading-events>
- <doc:Persistent-subscriptions>
- <doc:Managing-projections>
- <doc:User-management>
- <doc:Cluster-gossip>
- <doc:Server-statistics>
- <doc:Server-operations>
- <doc:Client-pools>
- <doc:Migration-guide>

## Architecture
- <doc:StreamsTarget-design>
- <doc:ProjectionsTarget-design>
- <doc:PersistentSubscriptionTarget-design>
- <doc:UsersTarget-design>
- <doc:OperationsTarget-design>

## Usage

Create one ``KurrentDBClient`` for your application and reuse it. Every operation starts from a value scoped to what it acts on — a stream, a projection, a subscription group — and the compiler only offers the operations that make sense for it.

### Streams

```swift
let settings: ClientSettings = "kurrentdb://localhost:2113?tls=false"
let client = KurrentDBClient(settings: settings)

// Append to a stream
try await client.streams(specified: "orders").append(events: [eventData])

// Read it back
for try await response in try await client.streams(specified: "orders").read() {
    print(try response.event.record)
}
```

### Persistent subscriptions

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)

// Create the group, then subscribe to it
let persistentSubscriptions = client.persistentSubscriptions(stream: "orders", group: "order-workers")
try await persistentSubscriptions.create()

let subscription = try await persistentSubscriptions.subscribe()

for try await result in subscription.events {
    // Handle the event, then acknowledge it...
    try await subscription.ack(readEvents: result.event)
    // ...or reject it:
    // try await subscription.nack(readEvents: result.event, action: .park, reason: "It failed.")
}
```

## What's new

### 2.4

- **Connection management.** Calls that return a single response share one connection per node; reads and subscriptions each get their own, so long-lived subscriptions never compete with other calls. ``KurrentDBClient/shutdown()`` closes every connection the client opened, makes later calls throw ``KurrentError/connectionClosed``, and can be called more than once. See <doc:Getting-started>.
- **Persistent subscriptions close when dropped.** A subscription's connection now closes once nothing references the subscription or its `events` stream (2.4.1).
- **Discovery retries wait.** Settings built in code now wait 100 ms between node-discovery attempts, like connection strings; before, they waited 100 µs, so retries were effectively immediate (2.4.2).
- **X.509 client certificates are sent.** `userCertFile` / `userKeyFile` now present the certificate in the TLS handshake (2.4.2).
- **`StreamFilter.onStreamName(prefixes:)`** accepts a variadic list, like `onEventType(prefixes:)`; `onStreamName(prefix:)` is deprecated (2.4.2).

### 2.3

- **`KurrentDBPool`.** Borrow a client for one of several independent KurrentDB instances, for example one per test. See <doc:Client-pools>.
- **Persistent subscription defaults fixed.** `messageTimeout` and `checkpointAfter` now default to 30 s and 2 s, matching the server (2.3.1).

### 2.2

- **`ClientSettings.fromEnv(key:)`** builds settings from a connection string in an environment variable.

### 2.1

- **Multi-stream writes.** `appendRecords(events:checks:)` appends atomically with cross-stream consistency checks (Dynamic Consistency Boundary, KurrentDB 26.1+); `batchAppend(events:)` pipelines many non-atomic appends. See <doc:Appending-events>.
- **Server-side `$all` filtering.** Set `filter` when reading `$all` to receive only matching stream names or event types. See <doc:Reading-events>.
- **Per-call credentials and bearer tokens.** Call `authenticated(_:)` on a `Streams`, `Projections` or other value to override credentials for calls made through it, including ``Authentication/bearer(token:)``.
- **`StreamFilter`.** Renamed from `SubscriptionFilter` (now deprecated); shared by subscriptions and filtered reads.

```swift
try await client.multiStreams.appendRecords(
    events: [
        StreamEvent(stream: "order-1", records: [record]),
    ],
    checks: [.streamState("customer-42", .streamExists)]
)

let filtered = try await client.allStreams.read {
    $0.filter = .onEventType(prefixes: "OrderPlaced")
}

try await client.streams(specified: "orders")
    .authenticated(.bearer(token: "user-access-token"))
    .append(events: [eventData])
```
