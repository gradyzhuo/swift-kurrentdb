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
let responses = try await client.readStream("some-stream"){
    $0
    .startFrom(revision: .start)
```

This will return an enumerable that can be iterated on:

```swift
for try await response in responses {
    if let readEvent = try response.event {
        let domainEvent = try readEvent.record.decode(to: TestEvent.self)
    }
}
```

There are a number of additional arguments you can provide when reading a stream, listed below.

#### maxCount (limit)
Passing in the max count will limit the number of events returned.

#### resolveLinkTos
When using projections to create new events, you can set whether the generated events are pointers to existing events. Setting this value to `true` tells KurrentDB to return the event as well as the event linking to it.

#### configureOperationOptions
You can use the configureOperationOptions argument to provide a function that will customise settings for each operation.

#### userCredentials
The userCredentials argument is optional. It is used to override the default credentials specified when creating the client instance.

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))

let client = KurrentDBClient(settings: settings)

let responses = try await client.readStream("some-stream"){
    $0
    .startFrom(revision: .start)
```

## Reading from a revision
Instead of providing the __StreamPosition__ you can also provide a specific stream revision as a big int (unsigned 64-bit integer).

```swift 
let readResponses = try await client.readStream("some-stream") {
    $0
    .startFrom(revision: .specified(10))
    .limit(20)
}
```


## Reading backwards
In addition to reading a stream forwards, streams can be read backwards. To read all the events backwards, set the _stream position_ to the end:

```swift
let responses = try await client.readStream("some-stream"){
    $0
    .startFrom(revision: .end)
    .backwards()
}

for try await response in responses {
    if let readEvent = try response.event {
        print("Event> \(try readEvent.record.decode(to: TestEvent.self))")
    }
}
```

> Tips: 
> Read one event backwards to find the last position in the stream.

## Checking if the stream exists
Reading a stream returns a `ReadStreamResult`, which contains a property `ReadState`. This property can have the value `StreamNotFound` or `Ok`.

It is important to check the value of this field before attempting to iterate an empty stream, as it will throw an exception.

For example:
```swift
let responses = try await client.readStream( "some-stream"){
    $0
    .startFrom(revision: .specified(10))
}


let stream = client.streams(of: .specified("some-stream"))
do{
    let responses = try await client.readStream( "some-stream"){
    $0
    .startFrom(revision: .specified(10))
}
    for try await response in responses {
        if let readEvent = try response.event {
            let testEvent = try readEvent.record.decode(to: TestEvent.self)
            print("Event> \(testEvent)")
        }
    }
}catch let error as EventStoreError{
    if case .resourceNotFound(let reason) = error {
        print("reason:", reason)
    }
}
```

> Console:
> reason: The name 'some-stream' of streams not found.

## Reading from the $all stream

Reading from the `$all` stream is similar to reading from an individual stream, but please note there are differences. One significant difference is the need to provide admin user account credentials to read from the `$all` stream. Additionally, you need to provide a transaction log position instead of a stream revision when reading from the `$all` stream.


### Reading forwards
The simplest way to read the `$all` stream forwards is to supply a read direction and the transaction log position from which you want to start. The transaction log postion can either be a stream position `Start` or a big int (unsigned 64-bit integer):

```swift
let responses = try await client.readAllStream(){
    $0
    .startFrom(position: .start)
}
```

You can iterate asynchronously through the result:
```swift
for try await response in responses {
    if let readEvent = try response.event {
        print("Event>", readEvent.record)
    }
}
```


#### maxCount (limit)
Passing in the max count will limit the number of events returned.

#### resolveLinkTos
When using projections to create new events, you can set whether the generated events are pointers to existing events. Setting this value to `true` tells KurrentDB to return the event as well as the event linking to it.

```swift
let responses = try await client.readAllStream(){
    $0
    .startFrom(position: .start)
    .resolveLinks()
}
```


#### configureOperationOptions
This argument is generic setting class for all operations that can be set on all operations executed against EventStoreDB.


#### userCredentials
The userCredentials argument is optional. It is used to override the default credentials specified when creating the client instance.

```swift
let settings: ClientSettings = "esdb://localhost:2113?tls=false"

let client = KurrentDBClient(
    settings: settings.authenticated(.credentials(username: "admin", password: "changeit"))
)

let responses = try await client.readAllStream(){
    $0
    .startFrom(position: .specified(commit: 1110, prepare: 1110))
}
```

### Reading backwards
In addition to reading the `$all` stream forwards, it can be read backwards. To read all the events backwards, set the _position_ to the end:

```swift
let responses = try await client.readAllStream(){
    $0
    .startFrom(position: .end)
}
```

> Tips:
Read one event backwards to find the last position in the $all stream.

### Handling system events
KurrentDB will also return system events when reading from the `$all` stream. In most cases you can ignore these events.

All system events begin with `$` or `$$` and can be easily ignored by checking the `EventType` property.

```swift
let responses = try await client.readAllStream(){
    $0
    .startFrom(position: .start)
}

for try await response in responses {
    guard let readEvent = try response.event,
          readEvent.record.eventType.hasPrefix("$") else {
        continue
    }
    print("Event>", readEvent.record)
}
```

## Architecture

For details on the target-based design of the Streams API, see <doc:StreamsTarget-design>.
