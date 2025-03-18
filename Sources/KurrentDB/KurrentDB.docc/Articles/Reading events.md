# Reading events

There are two options for reading events from EventStoreDB. You can either: 1. Read from an individual stream, or 2. Read from the $all stream, which will return all events in the store.

Each event in EventStoreDB belongs to an individual stream. When reading events, pick the name of the stream from which you want to read the events and choose whether to read the stream forwards or backwards.

All events have a StreamPosition and a Position. StreamPosition is a big int (unsigned 64-bit integer) and represents the place of the event in the stream. Position is the event's logical position, and is represented by CommitPosition and a PreparePosition. Note that when reading events you will supply a different "position" depending on whether you are reading from an individual stream or the $all stream.

> Tips: 
> Check [connecting to EventStoreDB instructions](<doc:Getting-started>) to learn how to configure and use the client SDK.

## Reading from a stream
You can read all the events or a sample of the events from individual streams, starting from any position in the stream, and can read either forward or backward. It is only possible to read events from a single stream at a time. You can read events from the global event log, which spans across streams. 


### Reading forwards
The simplest way to read a stream forwards is to supply a stream name, read direction, and revision from which to start. The revision can either be a stream position `Start` or a _big int_ (`UInt64`):
```swift
let stream = client.streams(of: "some-stream")
let responses = try await stream.read(from: .start)
```

This will return an enumerable that can be iterated on:

```swift
for try await response in responses {
    if case let .event(readEvent) = response {
        let domainEvent = try readEvent.record.decode(to: TestEvent.self)
    }
}
```

There are a number of additional arguments you can provide when reading a stream, listed below.

#### maxCount
Passing in the max count will limit the number of events returned.

#### resolveLinkTos
When using projections to create new events, you can set whether the generated events are pointers to existing events. Setting this value to `true` tells KurrentDB to return the event as well as the event linking to it.

#### configureOperationOptions
You can use the configureOperationOptions argument to provide a function that will customise settings for each operation.

#### userCredentials
The userCredentials argument is optional. It is used to override the default credentials specified when creating the client instance.

```swift
let settings:ClientSettings = .localhost().defaultUserCredentials(.init(username: "admin", password: "changeit"))

let client = KurrentDBClient(settings: settings)

let stream = client.streams(of: .specified("some-stream"))
let responses = try await stream.read(from: .start)
```

## Reading from a revision
Instead of providing the StreamPosition you can also provide a specific stream revision as a big int (unsigned 64-bit integer).

```swift 
let stream = client.streams(of: .specified("some-stream"))
let responses = try await stream.read(from: 10, directTo: .forward, options: .init().set(limit: 20))
```


