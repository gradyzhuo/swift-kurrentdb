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

### 3.0

- **Removed: the 1.x module and the deprecated names.** `KurrentDB_V1` is gone (migrate on 2.6 first: <doc:Migration-guide>); so are `certificate(path:)`, the misspelled `cerificates` / `cerificate(source:)` / `cerificate(path:)`, `KurrentError.CurrentRevisionOption`, `EventData.init(eventType:payload: Codable)`, `StreamFilter.onStreamName(prefix:)` and `SubscriptionFilter`. Each had a replacement in 2.x; the 3.0 migration article lists them. **Upgrade note:** events built with the removed `EventData` initialiser from a `Data` value were stored as base64 JSON strings — use `payload: .json(data)` to keep that format; `data:` stores the raw bytes.
- **Subscription notifications.** ``Streams/Subscription/messages`` delivers the server's `caughtUp`, `fellBehind` (KurrentDB 26.2.2+) and (for a filtered `$all` subscription) `checkpoint` notifications next to the events, as a ``Streams/Subscription/Message``, so a read model can tell when it is current and a filtered subscription can store a resume position while nothing matches. `events` is unchanged. See <doc:Reading-events>.
- **A subscription to a tombstoned stream ends with `resourceDeleted`.** When the stream a catch-up subscription follows is tombstoned, `events` now throws `KurrentError.resourceDeleted`, the error a read of a tombstoned stream throws, after delivering the events written before it; subscribing to an already tombstoned stream throws it from `subscribe`. **Upgrade note:** the `$streamDeleted` marker is no longer delivered as an event, and the raw `RPCError` that followed it is gone. Subscriptions to `$all` still deliver `$streamDeleted` as a system event. See <doc:Reading-events>.

### 2.6

- **Typed errors for deleted streams and revision conflicts.** A `read()` the server rejects throws the same `KurrentError` as `read().lazy` already did, instead of a raw `RPCError`: `resourceDeleted` for a tombstoned stream, `accessDenied` without permission. `delete` and `tombstone` report a revision conflict as `KurrentError.wrongExpectedVersion(expected:current:)`, the same case `append` throws, with `current` set to `.noStream` when the stream does not exist. **Upgrade note:** code that matched `KurrentError.grpcError` for a delete or tombstone revision conflict now receives `wrongExpectedVersion`.
- **`CurrentRevisionState`.** `KurrentError.CurrentRevisionOption` is renamed `KurrentError.CurrentRevisionState`, because it is the server's observed state, not an option. The old name remained as a deprecated typealias (removed in 3.0).
- **KurrentDB 26.2.** CI now also tests against KurrentDB 26.2, on a single node: 26.2 needs a Kurrent license to run a multi-node cluster. 26.2 rejects creating transient projections as deprecated, so `create(query:)` on a `.transient(name:)` target throws there.
- **Licensing.** The license file is now `LICENSE`, and a new `NOTICE` records the source and license of every bundled `.proto` file. The unused schema registry protos, the only ones under the Kurrent License v1, are removed. They were package-level only.

### 2.5

- **Lazy reads and backpressured subscriptions.** `read().lazy` streams events as you iterate and ends the RPC when the loop does, so memory no longer grows with the result; `read().buffered` (and plain `read()`) keep today's behaviour. Subscriptions are now backpressured with bounded memory. See <doc:Reading-events>.
- **Strict connection strings.** Connection strings are parsed according to RFC 3986: unknown, duplicate or invalid parameters throw, credentials and values are percent-decoded, and characters in a password can no longer change hosts or TLS settings. New `policy:` entry point (`.rfc3986`). **Upgrade note:** strings that used to be accepted may now throw — see <doc:Getting-started>.
- **`defaultDeadline` takes effect.** It now bounds calls that complete before they return (appends, deletes, management calls, `read()`); subscriptions, persistent-subscription reads, server statistics and `read().lazy` are not bounded by it.
- **Unreadable CA certificates are reported.** An unreadable `tlsCaFile` makes `parse` throw; `certificate(path:fallback:)` replaces `certificate(path:)`, which is deprecated (removed in 3.0) and refuses to connect instead of trusting the system roots.
- **One `gossipTimeout` default.** Connection strings now default to 3 seconds, like settings built in code (they used to default to 5).
- **Untrusted input no longer crashes or leaks.** Negative revisions or positions from the server, credentials that cannot be encoded, and connection strings in error messages are handled safely.

### 2.4

- **Reads share the connection.** `read()`, `readAll()`, projection statistics and user details now use the per-node shared connection instead of opening one connection per call; only subscriptions, persistent subscriptions and server statistics keep a dedicated connection. See <doc:Getting-started> (2.4.3).
- **Connection management.** Calls that return a single response and reads share one connection per node; subscriptions, persistent subscriptions and server statistics each get their own, so long-lived streams never compete with other calls. ``KurrentDBClient/shutdown()`` closes every connection the client opened, makes later calls throw ``KurrentError/connectionClosed``, and can be called more than once. See <doc:Getting-started>.
- **Persistent subscriptions close when dropped.** A subscription's connection now closes once nothing references the subscription or its `events` stream (2.4.1).
- **Discovery retries wait.** Settings built in code now wait 100 ms between node-discovery attempts, like connection strings; before, they waited 100 µs, so retries were effectively immediate (2.4.2).
- **X.509 client certificates are sent.** `userCertFile` / `userKeyFile` now present the certificate in the TLS handshake (2.4.2).
- **`StreamFilter.onStreamName(prefixes:)`** accepts a variadic list, like `onEventType(prefixes:)`; `onStreamName(prefix:)` is deprecated (2.4.2; removed in 3.0).

### 2.3

- **`KurrentDBPool`.** Borrow a client for one of several independent KurrentDB instances, for example one per test. See <doc:Client-pools>.
- **Persistent subscription defaults fixed.** `messageTimeout` and `checkpointAfter` now default to 30 s and 2 s, matching the server (2.3.1).

### 2.2

- **`ClientSettings.fromEnv(key:policy:)`** builds settings from a connection string in an environment variable.

### 2.1

- **Multi-stream writes.** `appendRecords(events:checks:)` appends atomically with cross-stream consistency checks (Dynamic Consistency Boundary, KurrentDB 26.1+); `batchAppend(events:)` pipelines many non-atomic appends. See <doc:Appending-events>.
- **Server-side `$all` filtering.** Set `filter` when reading `$all` to receive only matching stream names or event types. See <doc:Reading-events>.
- **Per-call credentials and bearer tokens.** Call `authenticated(_:)` on a `Streams`, `Projections` or other value to override credentials for calls made through it, including ``Authentication/bearer(token:)``.
- **`StreamFilter`.** Renamed from `SubscriptionFilter` (deprecated; removed in 3.0); shared by subscriptions and filtered reads.

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
