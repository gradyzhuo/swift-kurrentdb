# ``KurrentDB``

@Options(scope: local) {
    @TopicsVisualStyle(hidden)
}

A modern, type-safe Swift client for KurrentDB (formerly EventStoreDB), built on gRPC and Swift Concurrency.

## Articles
- <doc:Getting-started>
- <doc:Appending-events>
- <doc:Reading-events>
- <doc:Stream-metadata>
- <doc:Persistent-subscriptions>
- <doc:Managing-projections>
- <doc:User-management>
- <doc:Cluster-gossip>
- <doc:Server-statistics>
- <doc:Server-operations>
- <doc:Client-pools>
- <doc:Migrating-to-3.0>
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
for try await response in client.streams(specified: "orders").read() {
    print(try response.event.record)
}
```

### Persistent subscription groups

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

- **`read()` delivers lazily.** `read()` returns a ``Streams/ReadCall``, an `AsyncSequence` you iterate with `for try await`: events arrive as you iterate, with backpressure, and the RPC ends when the loop does, so memory no longer grows with the result. Off an actor it costs about what `.buffered` costs per event. `.buffered` keeps the whole-result form, for snapshots and results iterated later; `.lazy` is deprecated (drop it). `defaultDeadline` bounds establishing the read, from node selection to the server's first response, as one budget that is not retried; the iteration is not bounded by it. Errors after the server accepts the read are `KurrentError`, and a cancelled read throws `CancellationError`. `KurrentDBClient(settings:eventLoopGroup:)` replaces `numberOfThreads:`, and `shutdown()` no longer throws; it ends a read in progress with `connectionClosed`. See <doc:Reading-events>.
- **Removed: the 1.x module and the deprecated names.** `KurrentDB_V1` is gone (migrate on 2.6 first: <doc:Migration-guide>); so are these deprecated names, each replaced in 2.x: `certificate(path:)` (use `certificate(path:fallback:)`), the misspelled `cerificates` / `cerificate(source:)` / `cerificate(path:)` (`certificates` / `certificate(source:)` / `certificate(path:fallback:)`), `KurrentError.CurrentRevisionOption` (`KurrentError.CurrentRevisionState`), `EventData.init(eventType:payload: Codable)` (`payload: .json(value)`, which it forwarded to), `StreamFilter.onStreamName(prefix:)` (`onStreamName(prefixes:)`) and `SubscriptionFilter` (`StreamFilter`). One `KurrentDB_V1` call does not stop compiling: its `client.shutdown()` shut the server down, and without the import the same line closes the client instead (<doc:Migration-guide>). **Upgrade note:** events built with the removed `EventData` initialiser from a `Data` value were stored as base64 JSON strings — use `payload: .json(data)` to keep that format; `data:` stores the raw bytes.
- **Subscription notifications.** ``Streams/Subscription/messages`` delivers the server's `caughtUp`, `fellBehind` (KurrentDB 26.2.2+) and (for a filtered `$all` subscription) `checkpoint` notifications next to the events, as a ``Streams/Subscription/Message``, so a read model can tell when it is current and a filtered subscription can store a resume position while nothing matches. `events` is unchanged. See <doc:Reading-events>.
- **Notification payloads.** `caughtUp`, `fellBehind` and `checkpoint` carry ``Streams/Subscription/CaughtUp``, ``Streams/Subscription/FellBehind`` and ``Streams/Subscription/Checkpoint``: the server's `timestamp` and where to resume, `revision` on a stream subscription and `position` on `$all`. `checkpoint` carries a `Checkpoint`, not a bare ``StreamPosition``; read its `position`. On Swift 6.2.3 and later `Message` is `@nonexhaustive`: end every switch over it with `@unknown default`. See <doc:Reading-events>.
- **Stream metadata is stored in the server's format.** ``StreamMetadata`` holds the system fields and every other key of the JSON object stored in the stream's metadata stream, including keys other clients wrote and `$` keys a later server adds, so reading the metadata, changing it and writing it back no longer drops them. `maxAge` and `cacheControl` are written and read in whole seconds, as the server stores them, with any sub-second part truncated; up to 2.6.1, 2.x wrote Swift's `Duration` encoding and threw on metadata that held seconds. Custom keys are top-level keys holding any JSON value, and keys starting with `$` are reserved. The system fields can now be read (`maxCount`, `maxAge`, `truncateBefore`, `cacheControl`, `acl`), `==` compares the whole object, and `customProperties(_ [String: String])` is deprecated (removed in 4.0). Metadata is read as strictly as the server and the .NET client read it: `getMetadata()` throws `KurrentError.internalParsingError` for an object the server ignores as a whole, such as a duration that is not an integer or an `$acl` that is not an object of roles. **Removed:** `StreamMetadata.Acl.userStream` and `.systemStream`, which up to 2.6.1 wrote a string the server rejects, so it ignored the whole metadata, and in 2.6.2 no `$acl` and `$admins`; use `.serverDefault`, which removes `$acl` so the server applies the default from `$settings`, or `.stream(…)`. `StreamAcl.defaults` starts a stream's first ACL, and each permission is a `StreamAcl.Roles` value, `.defaults` (not stored, so `$settings` applies) or `.granted([…])`: the role builders take it, so array literals still compile and a `[String]` variable becomes `.granted(names)`, and the role properties return it instead of `[String]?`. `StreamMetadata`, `StreamAcl` and `Acl` are no longer `Codable`, since `JSONDecoder` and `JSONEncoder` do not read and write JSON as the server does, and `Acl` has no `rawValue`: read stored metadata with `StreamMetadata(data:)`, and print `String(reflecting: metadata)` to see the JSON that is sent. A role name that the server's JSON reader takes for a date, such as `"2024-01-01T00:00:00"`, is refused when read and when written. **Upgrade note:** `maxAge`, `cacheControl`, `.userStream` and `.systemStream` set by a Swift client up to 2.6.1 were stored in a form the server rejects (`Duration`'s `[high, low]` array, an `$acl` string). The server accepted those writes and then ignored the whole object: on those streams `$maxCount`, `$tb` and `$acl` were never enforced, and 3.0's `getMetadata()` throws for them. Read the latest event of `$$<stream>`, convert it and write the metadata again from 3.0, checking each value first: the rewrite enforces `$maxCount`, `$tb` and `$acl` for the first time. A client up to 2.6.1 throws from `getMetadata()` on metadata that holds durations in seconds, and every 2.x writer drops top-level custom keys (up to 2.6.1 it also stores the `[high, low]` form again): upgrade every Swift client that reads or writes a stream's metadata before you write it from 3.0. 2.x custom properties were nested under a `"customProperties"` key, and 3.0 reads top-level keys: rewrite them, reading the old ones with `customProperty("customProperties", as: [String: String].self)`. <doc:Migrating-to-3.0> shows the conversion; see also <doc:Stream-metadata>.
- **Typed custom metadata.** `customMetadata:` takes a ``CustomMetadata``: `try .json(value)` encodes any `Encodable` value, and `try CustomMetadata(data: data, format: .bytes)` carries bytes in another encoding. ``EventData`` accepts both; ``EventRecord`` accepts JSON only, so bytes metadata on a record does not compile, and an invalid value is refused when the record is created, not when it is appended. ``RecordedEvent/customMetadata(format:)`` reads it back, and `decode(_:)` gives your own type. *Upgrade note:* `customMetadata:` as `Data`, `EventRecord.setValue(_:forKey:)` and assigning to `EventRecord.properties` still work and are deprecated (removed in 4.0); `EventRecord(id:data:schema:properties:)` is removed, in favour of `EventRecord(id:data:schema:customMetadata:)`. Creating an ``EventRecord`` now throws ``KurrentError`` only: a payload that cannot be encoded is `KurrentError.underlyingError`, a new case whose `cause` is the `EncodingError`, where 2.x threw the `EncodingError` itself. See <doc:Appending-events> and <doc:Migrating-to-3.0>.
- **Migrating from 2.x.** <doc:Migrating-to-3.0> lists what to check before you upgrade, every place where a 2.x program that compiles against 3.0 behaves differently, and every removed declaration with its replacement, with the 2.x and the 3.0 code wherever the code changes.

### 2.6

- **Stream metadata the server applies.** `setMetadata` wrote `maxAge` and `cacheControl` as Swift `Duration` arrays, and `.userStream` and `.systemStream` as an `$acl` string. The server ignores the whole metadata object for either, so the `$maxCount`, `$tb` and `$acl` written with them were never enforced: the stream fell back to the server's default ACL, which under the default `$settings` lets every user read it. Durations are now whole seconds, `.userStream` writes no `$acl` (the server's `$userStreamAcl` default), and `.systemStream` writes `$admins` for every permission; a value the server cannot apply throws `encodingError`. `getMetadata` reads both formats, and a role written as a single string. **Upgrade note:** metadata that 2.6.1 or earlier wrote with `maxAge`, `cacheControl`, `.userStream` or `.systemStream` stays ignored by the server until it is written again. Once written with 2.6.2, `.userStream` reads back with no ACL and `.systemStream` as `.stream(_:)`; the old strings still read as `.userStream` and `.systemStream`. See <doc:Stream-metadata> (2.6.2).
- **Record metadata is kept.** `EventRecord(eventType:payload:customMetadata:)` and `EventRecord(eventData:)` dropped the metadata: every member on macOS, and every member that is not a string on Linux. `multiStreams.append` and `appendRecords` sent a property of a type they did not list (`Int64`, `Date`, a nested struct, an optional, …) as null, and `batchAppend` dropped a record's whole metadata when one value could not be serialised. Every property that encodes as JSON now reaches the server, nested objects and arrays included; NaN, an infinity or an integer beyond 64 bits makes the append throw `encodingError`, and `customMetadata:` throws when it is not a JSON object. `append` and `appendRecords` carry numbers as `Double`, so an integer beyond ±2^53 arrives rounded. **Upgrade note:** metadata that is not a JSON object, which used to be ignored, now throws. See <doc:Appending-events> (2.6.1).
- **`multiStreams.append` checks the expected revision and reports its errors.** The expected revision of each ``StreamEvent`` was not sent, so the append succeeded at any revision; a conflict now throws `KurrentError.wrongExpectedVersion(expected:current:)`. An append to a tombstoned stream throws `resourceDeleted` instead of a `grpcError` that was retried as a node failure, and the other Streams errors the server reports map to `resourceNotFound`, `resourceAlreadyExists` or `illegalStateError`. **Upgrade note:** an append whose expected revision no longer matches, which used to succeed, now throws. See <doc:Appending-events> (2.6.1).
- **A subscription to a tombstoned stream ends with `resourceDeleted`.** When the stream a catch-up subscription follows is tombstoned, `events` now throws `KurrentError.resourceDeleted`, the error a read of a tombstoned stream throws, after delivering the events written before it; subscribing to an already tombstoned stream throws it from `subscribe`. **Upgrade note:** the `$streamDeleted` marker is no longer delivered as an event, and the raw `RPCError` that followed it is gone. Subscriptions to `$all` still deliver `$streamDeleted` as a system event. See <doc:Reading-events> (2.6.1).

- **Typed errors for deleted streams and revision conflicts.** A `read()` the server rejects throws the same `KurrentError` as `read().lazy` already did, instead of a raw `RPCError`: `resourceDeleted` for a tombstoned stream, `accessDenied` without permission. `delete` and `tombstone` report a revision conflict as `KurrentError.wrongExpectedVersion(expected:current:)`, the same case `append` throws, with `current` set to `.noStream` when the stream does not exist. **Upgrade note:** code that matched `KurrentError.grpcError` for a delete or tombstone revision conflict now receives `wrongExpectedVersion`.
- **`CurrentRevisionState`.** `KurrentError.CurrentRevisionOption` is renamed `KurrentError.CurrentRevisionState`, because it is the server's observed state, not an option. The old name remained as a deprecated typealias (removed in 3.0).
- **KurrentDB 26.2.** CI now also tests against KurrentDB 26.2, on a single node: 26.2 needs a Kurrent license to run a multi-node cluster. 26.2 rejects creating transient projections as deprecated, so `create(query:)` on a `.transient(name:)` target throws there.
- **Licensing.** The license file is now `LICENSE`, and a new `NOTICE` records the source and license of every bundled `.proto` file. The unused schema registry protos, the only ones under the Kurrent License v1, are removed. They were package-level only.

### 2.5

- **Lazy reads and backpressured subscriptions.** `read().lazy` streams events as you iterate and ends the RPC when the loop does, so memory no longer grows with the result; `read().buffered` (and plain `read()`) keep today's behaviour (3.0: `read()` itself delivers lazily). Subscriptions are now backpressured with bounded memory. See <doc:Reading-events>.
- **Strict connection strings.** Connection strings are parsed according to RFC 3986: unknown, duplicate or invalid parameters throw, credentials and values are percent-decoded, and characters in a password can no longer change hosts or TLS settings. New `policy:` entry point (`.rfc3986`). **Upgrade note:** strings that used to be accepted may now throw — see <doc:Getting-started>.
- **`defaultDeadline` takes effect.** It now bounds calls that complete before they return (appends, deletes, management calls, `read()`); subscriptions, persistent-subscription reads, server statistics and `read().lazy` are not bounded by it (3.0: for `read()` it bounds establishing the call; `.buffered` keeps this bound, per attempt).
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

let filtered = client.allStreams.read {
    $0.filter = .onEventType(prefixes: "OrderPlaced")
}

try await client.streams(specified: "orders")
    .authenticated(.bearer(token: "user-access-token"))
    .append(events: [eventData])
```
