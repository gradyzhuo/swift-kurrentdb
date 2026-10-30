# Reading events

There are two ways to read events from KurrentDB: read from an individual stream, or read from the `$all` stream, which returns every event in the store. A catch-up subscription reads the same two ways and then keeps delivering new events as they are written (see Catch-up subscriptions below).

Each event belongs to an individual stream. When reading, you pick the stream and whether to read it forwards or backwards.

Every event has a stream revision and a position. The revision is an unsigned 64-bit integer giving the event's place in its stream. The position is the event's place in the global transaction log, made of a commit position and a prepare position. Reading an individual stream takes a revision; reading `$all` takes a position.

> Tip: See <doc:Getting-started> to learn how to configure and create a ``KurrentDBClient``.

## Reading from a stream

Get a ``Streams`` value for the stream with ``KurrentDBClient/streams(specified:)`` and call `read(configure:)`. The closure receives the read options as an `inout` value; anything you don't set keeps its default (forwards, from the start, no limit).

### Reading forwards

```swift
let responses = client.streams(specified: "some-stream").read {
    $0.revision = .start
}
```

`read` returns a ``Streams/ReadCall``, an `AsyncSequence` you iterate with `for try await`; the RPC opens at the first element and ends when the loop does:

<!-- snippet:continue -->
```swift
for try await response in responses {
    let readEvent = try response.event
    if let order = try readEvent.record.decode(to: OrderPlaced.self) {
        print(order)
    }
}
```

`response.event` throws if the server sent a link whose target event no longer exists.

### Read options

| Option | Default | Meaning |
|--------|---------|---------|
| `revision` | `.start` | Where to start: `.start`, `.end`, or `.specified(UInt64)` |
| `direction` | `.forward` | `.forward` or `.backward` |
| `limit` | `.max` | Maximum number of events to return |
| `resolveLinks` (also `resolveLinksEnabled`) | `false` | Return the linked event for link events created by projections |

### Overriding credentials for one call

Credentials set on ``ClientSettings`` apply to every call. To use different credentials for a single operation, call `authenticated(_:)` on the ``Streams`` value:

```swift
let responses = client.streams(specified: "some-stream")
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .read()
```

## Reading from a revision

Pass a specific revision to start from it:

```swift
let responses = client.streams(specified: "some-stream").read {
    $0.revision = .specified(10)
    $0.limit = 20
}
```

## Reading backwards

To read a stream backwards, start from the end and set the direction:

```swift
let responses = client.streams(specified: "some-stream").read {
    $0.revision = .end
    $0.direction = .backward
}

for try await response in responses {
    print(try response.event.record)
}
```

> Tip: Read one event backwards to find the last revision of a stream.

## Checking if the stream exists

Reading a stream that doesn't exist throws ``KurrentError/resourceNotFound(reason:)``. The error arrives while you iterate the results, not when you call `read`:

```swift
do {
    let responses = client.streams(specified: "some-stream").read {
        $0.revision = .specified(10)
    }
    for try await response in responses {
        print(try response.event.record)
    }
} catch KurrentError.resourceNotFound(let reason) {
    print("reason:", reason)
}
```

A stream that was tombstoned throws ``KurrentError/resourceDeleted(resource:)`` instead, and a read the server refuses — for example `$all` without credentials — throws ``KurrentError/accessDenied``. These also arrive while you iterate.

> Console:
> reason: The name 'some-stream' of streams not found.

## Reading from the $all stream

Reading `$all` works like reading an individual stream, with two differences: it needs admin credentials, and it starts from a transaction log position instead of a stream revision. Use ``KurrentDBClient/allStreams``.

### Reading forwards

```swift
let responses = client.allStreams.read {
    $0.position = .start
}

for try await response in responses {
    print("Event>", try response.event.record)
}
```

`$all` read options are `position` (`.start`, `.end`, or `.specified(commit:prepare:)`), `direction`, `limit`, `resolveLinksEnabled`, and `filter`.

To resolve link events, set `resolveLinksEnabled`:

```swift
let responses = client.allStreams.read {
    $0.position = .start
    $0.resolveLinksEnabled = true
}
```

To start from a known position:

```swift
let responses = client.allStreams
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .read {
        $0.position = .specified(commit: 1110, prepare: 1110)
    }
```

### Reading backwards

```swift
let responses = client.allStreams.read {
    $0.position = .end
    $0.direction = .backward
    $0.limit = 1
}
```

> Tip: Read one event backwards to find the last position in `$all`.

### Filtering on the server

Set `filter` to a ``StreamFilter`` to have the server return only events whose stream name or event type matches. Filtering on the server saves sending events you would throw away.

```swift
// Events whose type starts with "Order"
let orderEvents = client.allStreams.read {
    $0.filter = .onEventType(prefixes: "Order")
}

// Events from streams whose name matches a regular expression
let customerEvents = client.allStreams.read {
    $0.filter = .onStreamName(regex: "^customer-")
}
```

### Handling system events

`$all` also returns system events. Their event types start with `$`, so you can skip them by checking `eventType`:

```swift
let responses = client.allStreams.read {
    $0.position = .start
}

for try await response in responses {
    let readEvent = try response.event
    guard !readEvent.record.eventType.hasPrefix("$") else {
        continue
    }
    print("Event>", readEvent.record)
}
```

A server-side filter such as `.onEventType(regex: "^[^$]")` skips them without sending them to the client.

## Catch-up subscriptions

A subscription is a read that does not end. It starts where you tell it, delivers the events that are already there (the catch-up), then keeps delivering new events as they are written, all through one `AsyncThrowingStream`. Projections and read models follow the store this way. Call `subscribe(configure:)` on the same ``Streams`` values you read from; the closure receives the options as an `inout` value.

By default a subscription starts at the **end** of the stream, so `subscribe()` with no options delivers new events only. Set `revision` (`position` for `$all`) to catch up first.

### Subscribing to a stream

```swift
let subscription = try await client.streams(specified: "orders").subscribe {
    $0.revision = .start
}

for try await readEvent in subscription.events {
    if let order = try readEvent.record.decode(to: OrderPlaced.self) {
        print(order)
    }
}
```

`subscribe` returns once the server has confirmed the subscription and throws if it cannot be established, for example ``KurrentError/accessDenied`` for `$all` without credentials. After that, every error surfaces from `events` while you iterate: the connection dropping, or ``KurrentError/connectionClosed`` after ``KurrentDBClient/shutdown()``. The stream does not have to exist yet: a subscription to a stream that is created later delivers its first event. A soft delete does not end it either; events appended to the recreated stream keep arriving. Tombstoning the stream ends `events` with ``KurrentError/resourceDeleted(resource:)``, the error a read of a tombstoned stream throws, once the events written before it have been delivered; the `$streamDeleted` marker itself is not delivered. On `$all`, `$streamDeleted` is an ordinary system event about the stream it names, and the subscription continues.

The options are `revision` (`.start`, `.end`, or `.specified(UInt64)`), `resolveLinksEnabled` and `uuidOption`. `.specified(n)` starts **after** revision `n`, so the first event delivered is `n + 1`; a read with `.specified(n)` starts at `n`.

### Subscribing to $all

Subscribing to `$all` needs the same credentials as reading it, starts from a log position, and takes the same `filter` as a filtered read (see Filtering on the server):

```swift
let subscription = try await client.allStreams.subscribe {
    $0.position = .start
    $0.filter = .onEventType(prefixes: "Order")
}

for try await readEvent in subscription.events {
    print(readEvent.record.streamIdentifier.name, readEvent.record.eventType)
}
```

Without a filter, `$all` also delivers system events; `.excludeSystemEvents()` leaves them out on the server (see Handling system events). `.specified(commit:prepare:)` starts after that position, like `.specified(n)` on a stream.

### Resuming from a checkpoint

A subscription lives as long as its connection and your process. To carry on after a restart, store the revision of the last event you handled, together with the read model it updated so the two cannot drift apart, and start the next subscription from it. Because `.specified` starts after the given revision, the stored value is used as it is:

```swift
// The last revision handled, persisted with the read model; nil before the first run.
let checkpoint: UInt64? = nil

let subscription = try await client.streams(specified: "orders").subscribe {
    $0.revision = checkpoint.map { .specified($0) } ?? .start
}

for try await readEvent in subscription.events {
    // Update the read model, then store readEvent.record.revision as the new checkpoint.
    print("handled revision", readEvent.record.revision)
}
```

For `$all`, store `readEvent.record.position`, a ``StreamPosition`` with `commit` and `prepare`:

```swift
let checkpoint: StreamPosition? = nil

let subscription = try await client.allStreams.subscribe {
    $0.position = checkpoint.map { .specified(commit: $0.commit, prepare: $0.prepare) } ?? .start
    $0.filter = .excludeSystemEvents()
}

for try await readEvent in subscription.events {
    // Update the read model, then store readEvent.record.position as the new checkpoint.
    print("handled position", readEvent.record.position.commit)
}
```

Establishing a subscription is retried across nodes under the client's retry policy, like any other call; an established one is not re-established by the client. When `events` throws, decide whether to subscribe again from your checkpoint.

### Caught up, fell behind and checkpoints

Besides events, the server tells a subscription when it has delivered everything that was written before it and is now following live writes, and when writes have outpaced the consumer so that it is reading history again. ``Streams/Subscription/messages`` carries these notifications next to the events, as a ``Streams/Subscription/Message``; `events` is the same stream without them. Iterate one of the two, not both. A read model that rebuilds itself from the start can use `caughtUp` to know when it is current and may start serving:

```swift
let subscription = try await client.streams(specified: "orders").subscribe {
    $0.revision = .start
}

for try await message in subscription.messages {
    switch message {
    case let .event(readEvent):
        print("apply", readEvent.record.eventType)
    case .caughtUp:
        print("the read model is current")
    case .fellBehind:
        print("reading history again")
    case .checkpoint:
        break  // $all with a filter only
    }
}
```

KurrentDB 26.2.2 is the first server that sends `fellBehind`. An older one returns to catch-up silently, and `caughtUp` still follows once it is current again.

A `$all` subscription with a filter also reports checkpoints: the position up to which the server has scanned without a match. Store a checkpoint like the position of an event, so that after a restart a long stretch without matching events is not scanned again. The first one reported is the start position itself; how often the next ones arrive follows the filter's ``StreamFilter/max(_:)`` window and ``StreamFilter/checkpointIntervalMultiplier(_:)``:

```swift
let subscription = try await client.allStreams.subscribe {
    $0.position = .start
    $0.filter = .onEventType(prefixes: "Order").max(32).checkpointIntervalMultiplier(1)
}

for try await message in subscription.messages {
    switch message {
    case let .event(readEvent):
        // Update the read model, then store readEvent.record.position.
        print("handled", readEvent.record.position.commit)
    case let .checkpoint(position):
        // Nothing matched up to here: store position the same way.
        print("scanned up to", position.commit)
    case .caughtUp, .fellBehind:
        break
    }
}
```

### Stopping

```swift
let subscription = try await client.streams(specified: "orders").subscribe()

Task {
    try await Task.sleep(for: .seconds(60))
    subscription.cancel()
}

for try await readEvent in subscription.events {
    print(readEvent.record.eventType)
}
// cancel() ended `events`; the loop exited normally.
```

``Streams/Subscription/cancel()`` ends `events` and `messages` at once and the loop exits normally, as it does when your task is cancelled. An event that had already arrived from the server but was not yet handed to your code is dropped. After a `break` the subscription stays open while you hold it: call `cancel()` or let it go out of scope, which ends it too. ``KurrentDBClient/shutdown()`` ends every subscription the client opened.

### Backpressure

Subscriptions are backpressured: the client takes the next event from the server only when your code asks for it, so a slow consumer holds the server back through HTTP/2 flow control instead of growing client memory. The memory one subscription holds is bounded like a read's (see Bounded memory below). Each subscription has its own connection (see <doc:Getting-started>), so a long-lived subscription never competes with other calls.

The server's caught-up and fell-behind notifications are delivered through `messages` (above); `events` leaves them out.

## Bounded memory

`read()` delivers lazily: events arrive as you iterate, and the RPC ends when the loop does, so memory
does not grow with the result. Off an actor the loop reads grpc-swift's stream directly; on an actor each
element is handed over once. Either way, memory per read is bounded by the transport's inbound message queue
(10 messages by default), one HTTP/2 stream flow-control window (about 8 MiB by default) and, on an actor,
the one element in hand-off — not proportional to the result size.

```swift
var total = 0.0
for try await response in client.streams(specified: "orders").read() {
    if let order = try response.event.record.decode(to: OrderPlaced.self) {
        total += order.total
    }
}
```

``Streams/ReadCall`` is an `AsyncSequence`, so the usual operations apply and stop the RPC as soon as they
are done:

```swift
let cancelled = try await client.allStreams.read().first {
    try $0.event.record.eventType == "OrderCancelled"
}
let count = try await client.streams(specified: "orders").read { $0.limit = 1000 }.reduce(0) { n, _ in n + 1 }
let latest = try await client.streams(specified: "orders").read {
    $0.direction = .backward
    $0.revision = .end
}.prefix(10).reduce(into: [RecordedEvent]()) { $0.append(try $1.event.record) }
```

Calling `read` performs no network activity; each iteration opens its own RPC, so iterating the same call
twice reads the stream twice. The RPC ends when the iterator is released: after the loop, on `break`, on a
thrown error, or when your task is cancelled (`next()` then throws `CancellationError`). Only an iterator you
obtain with `makeAsyncIterator()` and keep keeps the RPC open; inside an actor, advance a stored iterator with
`next(isolation: self)`. A loop body that stops iterating (stuck on another `await`) also keeps the RPC open
until it continues or exits; the server is held by backpressure meanwhile.

`read()` calls share a second connection per node, the read connection, so a read that is still iterating
never makes appends or other calls wait. The read connection opens on the first `read()` to a node, so that
read also pays the connection setup (and the TLS handshake, on a secure connection). A read in progress holds
one HTTP/2 stream on it until the server has sent the rest of the result, and the server allows about 100 per
connection: further reads wait for one to end, and reads nested more than 100 deep deadlock — the innermost
waits for a slot only an outer read can free — so they hang unless `defaultDeadline` or a `CallOptions.timeout`
ends them with ``KurrentError/deadlineExceeded``. ``KurrentDBClient/shutdown()`` ends a read in progress with ``KurrentError/connectionClosed``.

`ClientSettings.defaultDeadline` bounds establishing a `read()` — from node selection to the server's first
response, waiting for a stream slot included — as one budget that is not retried; it then throws
``KurrentError/deadlineExceeded``. The iteration itself is not bounded by it. Before the server accepts the
read, node failures are retried under the client's retry policy; a call the server rejects (for example bad
credentials) fails at the first element. Every other error is a `KurrentError`, and later errors, including a
missing stream, surface while you iterate.

`.buffered` fetches the whole result before it returns, so memory grows with the result. Use it for a
snapshot, for a result you iterate later, or when the whole read should be bounded by `defaultDeadline`: there
the deadline bounds each attempt, from after node selection to the end of the result, so a read retried under
the retry policy can take up to `maxAttempts` × the deadline plus the backoff, with node rediscovery between
attempts.

```swift
let responses = try await client.streams(specified: "orders").read { $0.limit = 10 }.buffered
```

## Architecture

For details on the target-based design of the Streams API, see <doc:StreamsTarget-design>.
