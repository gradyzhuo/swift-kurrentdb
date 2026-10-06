# Reading events

There are two ways to read events from KurrentDB: read from an individual stream, or read from the `$all` stream, which returns every event in the store.

Each event belongs to an individual stream. When reading, you pick the stream and whether to read it forwards or backwards.

Every event has a stream revision and a position. The revision is an unsigned 64-bit integer giving the event's place in its stream. The position is the event's place in the global transaction log, made of a commit position and a prepare position. Reading an individual stream takes a revision; reading `$all` takes a position.

> Tip: See <doc:Getting-started> to learn how to configure and create a ``KurrentDBClient``.

## Reading from a stream

Get a ``Streams`` value for the stream with ``KurrentDBClient/streams(specified:)`` and call `read(configure:)`. The closure receives the read options as an `inout` value; anything you don't set keeps its default (forwards, from the start, no limit).

### Reading forwards

```swift
let responses = try await client.streams(specified: "some-stream").read {
    $0.revision = .start
}
```

`read` returns an `AsyncThrowingStream` you iterate with `for try await`:

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
let responses = try await client.streams(specified: "some-stream")
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .read()
```

## Reading from a revision

Pass a specific revision to start from it:

```swift
let responses = try await client.streams(specified: "some-stream").read {
    $0.revision = .specified(10)
    $0.limit = 20
}
```

## Reading backwards

To read a stream backwards, start from the end and set the direction:

```swift
let responses = try await client.streams(specified: "some-stream").read {
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
    let responses = try await client.streams(specified: "some-stream").read {
        $0.revision = .specified(10)
    }
    for try await response in responses {
        print(try response.event.record)
    }
} catch KurrentError.resourceNotFound(let reason) {
    print("reason:", reason)
}
```

> Console:
> reason: The name 'some-stream' of streams not found.

## Reading from the $all stream

Reading `$all` works like reading an individual stream, with two differences: it needs admin credentials, and it starts from a transaction log position instead of a stream revision. Use ``KurrentDBClient/allStreams``.

### Reading forwards

```swift
let responses = try await client.allStreams.read {
    $0.position = .start
}

for try await response in responses {
    print("Event>", try response.event.record)
}
```

`$all` read options are `position` (`.start`, `.end`, or `.specified(commit:prepare:)`), `direction`, `limit`, `resolveLinksEnabled`, and `filter`.

To resolve link events, set `resolveLinksEnabled`:

```swift
let responses = try await client.allStreams.read {
    $0.position = .start
    $0.resolveLinksEnabled = true
}
```

To start from a known position:

```swift
let responses = try await client.allStreams
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .read {
        $0.position = .specified(commit: 1110, prepare: 1110)
    }
```

### Reading backwards

```swift
let responses = try await client.allStreams.read {
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
let orderEvents = try await client.allStreams.read {
    $0.filter = .onEventType(prefixes: "Order")
}

// Events from streams whose name matches a regular expression
let customerEvents = try await client.allStreams.read {
    $0.filter = .onStreamName(regex: "^customer-")
}
```

### Handling system events

`$all` also returns system events. Their event types start with `$`, so you can skip them by checking `eventType`:

```swift
let responses = try await client.allStreams.read {
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

## Bounded memory: `read().lazy`

`read()` fetches the whole result before it returns, so memory grows with the result. For large
reads use the lazy form: events arrive as you iterate, memory is bounded by a small hand-off plus
one HTTP/2 flow-control window (about 8 MiB with the transport's default window), and the RPC ends when the loop does.

```swift
var total = 0.0
for try await response in client.streams(specified: "orders").read().lazy {
    if let order = try response.event.record.decode(to: OrderPlaced.self) {
        total += order.total
    }
}
```

`lazy` is an `AsyncSequence`, so the usual operations apply and stop the RPC as soon as they are
done:

```swift
let cancelled = try await client.allStreams.read().lazy.first {
    try $0.event.record.eventType == "OrderCancelled"
}
let count = try await client.streams(specified: "orders").read { $0.limit = 1000 }.lazy.reduce(0) { n, _ in n + 1 }
let latest = try await client.streams(specified: "orders").read {
    $0.direction = .backward
    $0.revision = .end
}.lazy.prefix(10).reduce(into: [RecordedEvent]()) { $0.append(try $1.event.record) }
```

The RPC ends when the iterator is released: after the loop, on `break`, on a thrown error, or when
your task is cancelled (`next()` then throws `CancellationError`). Only an iterator you obtain with
`makeAsyncIterator()` and keep keeps the RPC open. A loop body that stops iterating (stuck on another `await`) also keeps the RPC open until it continues or exits; the server is held by backpressure meanwhile. Many concurrent `.lazy` reads with slow loop bodies each hold an HTTP/2 stream on the shared connection for as long as they iterate. A call the server rejects before accepting it
(for example bad credentials) fails at the first element; only node failures are retried under the client's retry policy.
Later errors, including a missing stream, surface while you iterate, as with `read()`.

`read().buffered` is the explicit spelling of what `read()` does today:

```swift
let responses = try await client.streams(specified: "orders").read { $0.limit = 10 }.buffered
```

To hold a prepared read without iterating, spell its type: `let call: Streams<SpecifiedStream>.ReadCall = stream.read()`.

### Behaviour changes (since the backpressured subscription)

`Subscription.cancel()` now ends the stream without delivering an already-buffered event (at most one).

### Roadmap

In 3.0 `read()` itself delivers lazily; code that needs the whole result up front will write
`.buffered`. See `docs/adr/0001-read-becomes-lazy-in-3-0.md`. Subscriptions already apply the same
backpressure: a slow consumer is backpressured through HTTP/2 flow control instead of growing client memory.

## Architecture

For details on the target-based design of the Streams API, see <doc:StreamsTarget-design>.
