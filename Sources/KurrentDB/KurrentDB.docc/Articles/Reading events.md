# Reading events

There are two ways to read events from KurrentDB: read from an individual stream, or read from the `$all` stream, which returns every event in the store.

Each event belongs to an individual stream. When reading, you pick the stream and whether to read it forwards or backwards.

Every event has a stream revision and a position. The revision is an unsigned 64-bit integer giving the event's place in its stream. The position is the event's place in the global transaction log, made of a commit position and a prepare position. Reading an individual stream takes a revision; reading `$all` takes a position.

> Tip: See <doc:Getting-started> to learn how to configure and create a ``KurrentDBClient``.

## Reading from a stream

Get a ``Streams`` value for the stream with ``KurrentDBClient/streams(specified:)`` and call `read`. Events reach the closure you pass as `body` while they arrive, with backpressure: buffered memory is bounded by the hand-off capacity plus one HTTP/2 stream flow-control window (after which the server stops sending). When the closure returns or throws, the RPC has ended and its connection is released.

An optional first closure receives the read options as an `inout` value; anything you don't set keeps its default (forwards, from the start, no limit).

### Reading forwards

```swift
try await client.streams(specified: "some-stream").read {
    $0.revision = .start
} body: { events in
    for try await response in events {
        let readEvent = try response.event
        if let order = try readEvent.record.decode(to: OrderPlaced.self) {
            print(order)
        }
    }
}
```

`events` is an `AsyncThrowingStream` you iterate with `for try await`. It is valid only inside the closure. `response.event` throws if the server sent a link whose target event no longer exists.

The closure's return value is returned by `read`, so you can compute a result without keeping the events:

```swift
let total = try await client.streams(specified: "orders").read { events in
    var total = 0.0
    for try await response in events {
        let order = try response.event.record.decode(to: OrderPlaced.self)
        total += order?.total ?? 0
    }
    return total
}
```

> Note: A closure that is a single expression and also valid as the options closure (for example `{ events in events }`) resolves to the deprecated buffered `read(configure:)`. Pass the labels explicitly, `read(configure: { _ in }, body: { events in ... })`, if you need that form. Escaping the stream out of the closure is not useful anyway: it ends as soon as the closure returns.

### Errors and cancellation

Errors your closure throws are rethrown unchanged. A call the server rejects before accepting it (for example bad credentials) or a connection failure is thrown by `read` before your closure runs, as ``KurrentError``; node failures among them follow the client's retry policy. Errors after that, including a missing stream, surface while you iterate. If your task is cancelled, `read` throws `CancellationError` and the closure's result is discarded. A closure that stops iterating keeps the RPC open until it returns.

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
try await client.streams(specified: "some-stream")
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .read { events in
        for try await response in events {
            print(try response.event.record)
        }
    }
```

## Reading from a revision

Pass a specific revision to start from it:

```swift
try await client.streams(specified: "some-stream").read {
    $0.revision = .specified(10)
    $0.limit = 20
} body: { events in
    for try await response in events {
        print(try response.event.record)
    }
}
```

## Reading backwards

To read a stream backwards, start from the end and set the direction:

```swift
try await client.streams(specified: "some-stream").read {
    $0.revision = .end
    $0.direction = .backward
} body: { events in
    for try await response in events {
        print(try response.event.record)
    }
}
```

> Tip: Read one event backwards to find the last revision of a stream.

## Checking if the stream exists

Reading a stream that doesn't exist throws ``KurrentError/resourceNotFound(reason:)``. The error arrives while you iterate the results, not when you call `read`, so it is thrown out of your closure and `read` rethrows it:

```swift
do {
    try await client.streams(specified: "some-stream").read {
        $0.revision = .specified(10)
    } body: { events in
        for try await response in events {
            print(try response.event.record)
        }
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
try await client.allStreams.read {
    $0.position = .start
} body: { events in
    for try await response in events {
        print("Event>", try response.event.record)
    }
}
```

`$all` read options are `position` (`.start`, `.end`, or `.specified(commit:prepare:)`), `direction`, `limit`, `resolveLinksEnabled`, and `filter`.

To resolve link events, set `resolveLinksEnabled`:

```swift
try await client.allStreams.read {
    $0.position = .start
    $0.resolveLinksEnabled = true
} body: { events in
    for try await response in events {
        print(try response.event.record)
    }
}
```

To start from a known position:

```swift
try await client.allStreams
    .authenticated(.credentials(username: "admin", password: "changeit"))
    .read {
        $0.position = .specified(commit: 1110, prepare: 1110)
    } body: { events in
        for try await response in events {
            print(try response.event.record)
        }
    }
```

### Reading backwards

```swift
try await client.allStreams.read {
    $0.position = .end
    $0.direction = .backward
    $0.limit = 1
} body: { events in
    for try await response in events {
        print(try response.event.record)
    }
}
```

> Tip: Read one event backwards to find the last position in `$all`.

### Filtering on the server

Set `filter` to a ``StreamFilter`` to have the server return only events whose stream name or event type matches. Filtering on the server saves sending events you would throw away.

```swift
// Events whose type starts with "Order"
let orderEventCount = try await client.allStreams.read {
    $0.filter = .onEventType(prefixes: "Order")
} body: { events in
    try await events.reduce(0) { count, _ in count + 1 }
}

// Events from streams whose name matches a regular expression
let customerEventCount = try await client.allStreams.read {
    $0.filter = .onStreamName(regex: "^customer-")
} body: { events in
    try await events.reduce(0) { count, _ in count + 1 }
}
```

### Handling system events

`$all` also returns system events. Their event types start with `$`, so you can skip them by checking `eventType`:

```swift
try await client.allStreams.read {
    $0.position = .start
} body: { events in
    for try await response in events {
        let readEvent = try response.event
        guard !readEvent.record.eventType.hasPrefix("$") else {
            continue
        }
        print("Event>", readEvent.record)
    }
}
```

A server-side filter such as `.onEventType(regex: "^[^$]")` skips them without sending them to the client.

Subscriptions apply the same backpressure, with no API change.

## Deprecated: read() returning a stream

`read(configure:)` without a closure body returns an `AsyncThrowingStream` and is deprecated. It buffers the whole result before returning: memory grows with the result, and the RPC is already over when you iterate. It remains available, with unchanged behaviour, until 3.0; use the closure form above instead.

```swift
let responses = try await client.streams(specified: "some-stream").read {
    $0.revision = .start
}

for try await response in responses {
    print(try response.event.record)
}
```

## Architecture

For details on the target-based design of the Streams API, see <doc:StreamsTarget-design>.
