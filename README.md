[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)
# EventStoreDB-Swift
[EventStore](https://www.eventstore.com) [gRPC](https://github.com/grpc/grpc-swift.git) Client SDK in Swift.


### Getting the gRPC library

#### Swift Package Manager

The Swift Package Manager is the preferred way to get EventStoreDB. Simply add the package dependency to your Package.swift:

```swift
dependencies: [
  .package(url: "https://github.com/gradyzhuo/eventstoredb-swift.git", branch: "main")
]
```
...and depend on "EventStoreDB" in the necessary targets:

```swift
.target(
  name: ...,
  dependencies: [.product(name: "EventStoreDB", package: "eventstoredb-swift")]
]
```

### Examples

#### ClientSettings

```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.

EventStoreDB.using(settings: .parse(connectionString: "esdb://admin:changeit@localhost:2113"))

// convenience 
// EventStoreDB.using(settings: "esdb://admin:changeit@localhost:2113".parse())

// using string literal 
// EventStoreDB.using(settings: "esdb://admin:changeit@localhost:2113")


//or 
// EventStoreDB.using(settings: .localhost(userCredentials: .init(username: "admin", password: "changeit"))

//or add ssl file by path
// EventStoreDB.using(settings: .localhost(userCredentials: .init(username: "admin", password: "changeit"), trustRoots: .file("...filePath...")))

//or add ssl file with bundle
// EventStoreDB.using(settings: .localhost(userCredentials: .init(username: "admin", password: "changeit"), trustRoots: .fileInBundle(forResource: "ca", withExtension: "crt", inBundle: .main)))
```

#### Appending Event

```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
EventStoreDB.using(settings: .localhost())


// Create the data array of events.
let events:[EventData] = [
            .json(id: .init(
                uuidString: "b989fe21-9469-4017-8d71-9820b8dd1164")!,
                type: "ItemAdded",
                  content: ["Description": "Xbox One S 1TB (Console)"]),
            .json(id: .init(
                uuidString: "b989fe21-9469-4017-8d71-9820b8dd1174")!,
                type: "ItemAdded",
                content: "Gears of War 4")
        ]

let streamName = "stream_for_testing"
let client = try EventStoreDB.Client()

let appendResponse = try await client.appendTo(streamName: streamName, events: events) { options in
    options.expectedRevision(.any)
}

```

#### Read Event

```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
EventStoreDB.using(settings: .localhost())

let streamName = "stream_for_testing"

//Check the event is appended into testing stream.
let readResponses = try client.read(streamName: streamName, cursor: .end) { options in
    options.set(uuidOption: .string)
        .countBy(limit: 1)
}

for await response in readResponses {
    //handle response
}
```

#### PersistentSubscriptions
##### Create
```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
EventStoreDB.using(settings: .localhost())

let streamName = "stream_for_testing"

let client = try EventStoreDB.Client()
try await client.createPersistentSubscription(streamName: streamName, groupName: "mytest", options: .init())

```

##### Subscribe
```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
EventStoreDB.using(settings: .localhost())

let streamName = "stream_for_testing"

let client = try EventStoreDB.Client()

let subscription = try await client.subscribePersistentSubscriptionTo(.specified(streamName), groupName: "mytest")

for try await result in subscription {
    // handle result
    
    // ack the readEvent if succeed 
    try await subscription.ack(readEvents: result.event)
    // else nack thr readEvent if not succeed.
    try await subscription.nack(readEvents: result.event, action: .park, reason: "It's failed.")
}
```
