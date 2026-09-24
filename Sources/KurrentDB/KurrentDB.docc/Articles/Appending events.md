# Appending events

> Tip: See <doc:Getting-started> to learn how to configure and create a ``KurrentDBClient``.

## Append your first event

The simplest way to append an event is to create an ``EventData`` value and pass it to `append(events:configure:)` on the ``Streams`` value for the stream:

<!-- snippet:toplevel -->
```swift
struct TestEvent: Codable, Sendable {
    let id: String
    let note: String
}
```

```swift
let event = EventData(
    eventType: "TestEvent",
    model: TestEvent(id: "1", note: "I wrote my first event!")
)

try await client.streams(specified: "some-stream").append(events: [event]) {
    $0.expectedRevision = .noStream
}
```

`append` takes an array of events (or a variadic list), so you can save several events in a single atomic write. The closure configures the append options as an `inout` value; leave it out to append with no expectation about the stream's state.

## Working with EventData

Events appended to KurrentDB are wrapped in an ``EventData`` value. It holds the event's ID, its type, its payload, and optional metadata.

### id

A `UUID` that uniquely identifies the event. It defaults to a new random `UUID`. If two events with the same ID are appended to the same stream in quick succession, KurrentDB appends only one of them.

For example, the following code appends a single event:

```swift
let event = EventData(
    id: UUID(),
    eventType: "TestEvent",
    model: TestEvent(id: "1", note: "I wrote my first event!")
)

try await client.streams(specified: "some-stream").append(events: event, event)
```

### eventType

A string that identifies the kind of event. Using the Swift type name is convenient for serialising and deserialising, but it couples storage to your code: renaming or versioning the type later becomes harder. Prefer a stable name you choose explicitly.

### Payload

Storing events as JSON lets you use all of KurrentDB's features, such as projections. You can create an ``EventData`` from:

- a `Codable` model, encoded as JSON: `EventData(eventType:model:)`
- raw bytes with a content type: `EventData(eventType:data:contentType:)` or `EventData(eventType:bytes:contentType:)`
- an ``EventData/Payload`` value: `EventData(eventType:payload:)`

```swift
let fromModel = EventData(eventType: "TestEvent", model: TestEvent(id: "1", note: "json"))

let fromData = EventData(
    eventType: "TestEvent",
    data: Data(#"{"id":"2","note":"raw"}"#.utf8),
    contentType: .json
)
```

### Metadata

Information that belongs with the event but isn't part of it — correlation IDs, causation IDs, access information — goes in `customMetadata`, a separate byte array stored alongside the event:

```swift
let metadata = try JSONEncoder().encode(["correlationId": "abc-123"])

let event = EventData(
    eventType: "TestEvent",
    model: TestEvent(id: "1", note: "with metadata"),
    customMetadata: metadata
)
```

## Handling concurrency

When appending, you can state what you expect the stream's state to be. If the stream isn't in that state, the append fails with ``KurrentError/wrongExpectedVersion(expected:current:)``.

For example, appending twice while expecting that the stream doesn't exist fails on the second append:

```swift
let stream = client.streams(specified: "same-event-stream")

try await stream.append(events: EventData(eventType: "some-event", model: TestEvent(id: "1", note: "some value"))) {
    $0.expectedRevision = .noStream
}

// Throws KurrentError.wrongExpectedVersion
try await stream.append(events: EventData(eventType: "some-event", model: TestEvent(id: "2", note: "some other value"))) {
    $0.expectedRevision = .noStream
}
```

``StreamRevision`` has four cases:

| Case | The append succeeds when |
|------|--------------------------|
| `.any` | always (the default) |
| `.noStream` | the stream doesn't exist yet |
| `.streamExists` | the stream exists |
| `.at(UInt64)` | the stream's last event is at exactly this revision |

`.at` gives you optimistic concurrency: read the stream's current revision, and when you write back, the append fails if someone else wrote in the meantime.

```swift
let stream = client.streams(specified: "concurrency-stream")

let responses = try await stream.read {
    $0.revision = .end
    $0.direction = .backward
    $0.limit = 1
}

for try await response in responses {
    let revision = try response.event.record.revision

    // Succeeds: nobody else has written since we read `revision`.
    try await stream.append(events: EventData(eventType: "some-event", model: TestEvent(id: "1", note: "clientOne"))) {
        $0.expectedRevision = .at(revision)
    }

    // Throws KurrentError.wrongExpectedVersion: the stream moved past `revision`.
    try await stream.append(events: EventData(eventType: "some-event", model: TestEvent(id: "2", note: "clientTwo"))) {
        $0.expectedRevision = .at(revision)
    }
}
```

The ``Streams/Append/Response`` returned by `append` carries the stream's new `currentRevision` and the commit `position`.

## User credentials

Credentials set on ``ClientSettings`` apply to every call:

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))

let client = KurrentDBClient(settings: settings)

try await client.streams(specified: "some-stream").append(events: [event])
```

To use different credentials for a single call, call `authenticated(_:)` on the ``Streams`` value. The override applies only to calls made through the returned value:

```swift
try await client.streams(specified: "some-stream")
    .authenticated(.credentials(username: "ops", password: "secret"))
    .append(events: [event])
```

For TLS and remote connections, see <doc:Getting-started>.

## Appending to several streams

``KurrentDBClient/multiStreams`` appends to more than one stream in one call. Each ``StreamEvent`` names its target stream, the ``EventRecord`` values to write, and optionally an expected revision. There are three ways to send them, with different guarantees:

| Method | Atomic | Server |
|--------|--------|--------|
| `append(events:)` | Yes — all streams or none | KurrentDB 25.1+ |
| `appendRecords(events:checks:)` | Yes, plus consistency checks on any stream | KurrentDB 26.1+ |
| `batchAppend(events:)` | No — each item succeeds or fails on its own | Any supported server |

```swift
let record = try EventRecord(eventType: "OrderPlaced", payload: .json(OrderPlaced(orderId: "order-1")))

try await client.multiStreams.append(events: [
    StreamEvent(stream: "order-1", records: [record], expectedRevision: .noStream),
    StreamEvent(stream: "audit", records: [record]),
])
```

### AppendRecords — Dynamic Consistency Boundary

`appendRecords(events:checks:)` commits atomically and lets the write depend on streams it doesn't write to. Every ``StreamEvent`` whose expected revision isn't `.any` becomes a check on its own stream; ``ConsistencyCheck`` values in `checks` can name any other stream. If any check fails, nothing is written and the call throws ``KurrentError/consistencyViolation(violations:)`` listing every failed check.

```swift
try await client.multiStreams.appendRecords(
    events: [
        StreamEvent(stream: "order-1", records: [record]),
    ],
    checks: [
        // Only place the order while the customer's stream is still where we read it.
        .streamState("customer-42", .at(7)),
    ]
)
```

### BatchAppend

`batchAppend(events:)` pipelines many appends over one call for throughput. It is **not atomic**: some items can succeed while others fail. Conflicts on individual items don't throw — inspect the response instead. Only transport failures throw.

```swift
let response = try await client.multiStreams.batchAppend(events: [
    StreamEvent(stream: "orders", records: [record]),
    StreamEvent(stream: "audit", records: [record]),
])

for failure in response.failed {
    print(failure.streamIdentifier.name, failure.message)
}
```

## Architecture

For details on the target-based design of the Streams API, see <doc:StreamsTarget-design>.
