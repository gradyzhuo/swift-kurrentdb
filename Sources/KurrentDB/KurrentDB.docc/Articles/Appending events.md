# Appending events


> Tips: Check the Getting Started guide to learn how to configure and use the client SDK.

## Append your first event
The simplest way to append an event to KurrentDB is to create an `EventData` object and call ``Streams/append(events:options:)`` method from ``KurrentDBClient/streams(of:)``.

```swift
let data = TestEvent(
    id: "1",
    note: "I wrote my first event!"
)

let event = EventData(
    id: UUID(),
    eventType: "\(TestEvent.self)",
    payload: data
)

try await client.appendStream("some-stream", events: event){
    $0.revision(expected: .noStream)
}
```

Append to streams takes a collection of `EventData`, which allows you to save more than one event in a single batch.

Outside the example above, other options exist for dealing with different scenarios.

## Working with EventData

Events appended to KurrentDB must be wrapped in an `EventData` instance. This allows you to specify the event's content, the type of event, and whether it's in JSON format. In its simplest form, you need three arguments: `eventId`, `type`, and `payload`.


### eventId
This takes the format of a `UUID` and is used to uniquely identify the event you are trying to append. If two events with the same Uuid are appended to the same stream in quick succession, KurrentDB will only append one of the events to the stream.

For example, the following code will only append a single event:

```swift
let data = TestEvent(
    id: "1",
    note: "I wrote my first event!"
)

let event = EventData(
    id: UUID(),
    eventType: "\(TestEvent.self)",
    payload: data
)

let copiedEvent = event

try await client.appendStream("some-stream", events: event, copiedEvent)
```

### type
Each event should be supplied with an event type. This unique string is used to identify the type of event you are saving.

It is common to see the explicit event code type name used as the type as it makes serialising and de-serialising of the event easy. However, we recommend against this as it couples the storage to the type and will make it more difficult if you need to version the event at a later date.

### payload 

Representation of your event data. It is recommended that you store your events as JSON objects. This allows you to take advantage of all of KurrentDB's functionality, such as projections. That said, you can save events using whatever format suits your workflow. Eventually, the data will be stored as encoded bytes.
The payload in EventData conforms to the Codable protocol, which means you can use any type that can be encoded to `JSON` or decoded from `JSON` by case json or passing a decoded data of `JSON` by `binary` case.

```swift
extension EventData {
    public enum Payload: Sendable {
        case data(Data)
        case json(Codable & Sendable)
        // ...
    }
}
```


### metadata
Storing additional information alongside your event that is part of the event itself is standard practice. This can be correlation IDs, timestamps, access information, etc. `KurrentDB` allows you to store a separate byte array containing this information to keep it separate.




## Handling concurrency
When appending events to a stream, you can supply a stream state or stream revision. Your client uses this to inform EventStoreDB of the state or version you expect the stream to be in when appending an event. If the stream isn't in that state, an exception will be thrown.

For example, if you try to append the same record twice, expecting both times that the stream doesn't exist, you will get an exception on the second:

```swift
let data = TestEvent(
    id: "1",
    note: "some value"
)

let event = EventData(
    id: UUID(),
    eventType: "some-event",
    payload: data
)

try await client.appendStream("same-event-stream", events: event){
    $0.revision(expected: .noStream)
}

let data2 = TestEvent(
    id: "2",
    note: "some other value"
)

let event2 = EventData(
    id: UUID(),
    eventType: "some-event",
    payload: data2
)

try await client.appendStream("same-event-stream", events: event2){
    $0.revision(expected: .noStream)
}

```

There are three available stream states:

- any
- noStream
- streamExists
- revision(UInt64)

```swift
public enum Rule: Sendable {
    case any
    case noStream
    case streamExists
    case revision(UInt64)
}
```

This check can be used to implement optimistic concurrency. When retrieving a stream from `KurrentDB`, note the current version number. When you save it back, you can determine if somebody else has modified the record in the meantime.


```swift
let stream = client.streams(of: .specified("concurrency-stream"))

if case let .event(event) = try await client.readStream("concurrency-stream"){ $0.startFrom(revision: .end) }.first{ _ in true} {
    let data = TestEvent(
        id: "1",
        note: "clientOne"
    )

    let revision = event.record.revision

    try await client.appendStream("concurrency-stream", events: [
            .init(
                id: UUID(),
                eventType: "some-event",
                payload: data)
        ]) {
        $0.revision(expected: .revision(revision))
    }
    
    let data2 = TestEvent(
        id: "2",
        note: "clientTwo"
    )

    try await client.appendStream("concurrency-stream", events: [
            .init(
                id: UUID(),
                eventType: "some-event",
                payload: data2)
        ]) {
        $0.revision(expected: .revision(revision))
    }
}
```

## User credentials
You can provide user credentials to append the data as follows. This will override the default credentials set on the connection.

```swift
let settings:ClientSettings = .localhost().authenticated(.credentials(username: "admin", password: "changeit"))

let client = KurrentDBClient(settings: settings)

try await client.appendStream("some-stream", events: [
        .init(
            id: UUID(),
            eventType: "some-event",
            payload: data2)
])
```

## Architecture

For details on the target-based design of the Streams API, see <doc:StreamsTarget-design>.
