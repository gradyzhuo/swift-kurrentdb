[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)
[![Swift-build-testing](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml)



# KurrentDB 
Hi, this is [Kurrent](https://www.kurrent.io/) (formerly: EventStoreDB) Database [gRPC](https://github.com/grpc/grpc-swift.git) Client SDK in Swift.

Kurrent is the first and only event-native data platform. It is built to store and stream data as events for use in downstream use cases such as advanced analytics, microservices and AI/ML initiatives.

## Implementation Status
### Client Settings
|Feature|Implemented|
|----|----|
|ConnectionString parsed|✅|
|Endpoint (ip, port)|✅|
|UserCredentials ( username, password )|✅|
|Gossip ClusterMode ||

### Stream
|Feature|Implemented|
|----|----|
|Append|✅|
|Read|✅|
|Metadata|✅|
|Subscribe Specified Stream|✅|
|Subscribe All Stream|✅|
|BatchAppend||

### Projection
|Feature|Implemented|
|----|----|
|Create|✅|
|Update|✅|
|Result|✅|
|Delete|✅|
|Enable|✅|
|Disable|✅|
|State|✅|
|Statistics|✅|
|Reset|✅|
|RestartSubsystem|✅|

### PersistentSubscriptions
|Feature|Implemented|
|----|----|
|Create|✅|
|Delete|✅|
|GetInfo|✅|
|List|✅|
|Read|✅|
|ReplayParked|✅|
|RestartSubsystem|✅|
|Subscribe|✅|
|Update|✅|


### User
|Feature|Implemented|
|----|----|
|Create|✅|
|Details|✅|
|ChangePassword||
|Disable||
|Enable||
|ResetPassword||
|Update||

## Getting the library

### Swift Package Manager

The Swift Package Manager is the preferred way to get EventStoreDB. Simply add the package dependency to your Package.swift:

```swift
dependencies: [
  .package(url: "https://github.com/gradyzhuo/eventstoredb-swift.git", from: "1.0.0-beta.2")
]
```
...and depend on "EventStoreDB" in the necessary targets:

```swift
.target(
  name: ...,
  dependencies: [.product(name: "EventStoreDB", package: "eventstoredb-swift")]
]
```

## Examples

### The library name to import.

`Version: 1.0.0`

```
import KurrentDB
```

`Version: 0.6.x`
```
import EventStoreDB
```


### ClientSettings

`Version: 1.0.0 && 0.6.x`

```swift
// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .parse(connectionString: "esdb://admin:changeit@localhost:2113")

// convenience 
let settings: ClientSettings = "esdb://admin:changeit@localhost:2113".parse()

// using string literal 
let settings: ClientSettings = "esdb://admin:changeit@localhost:2113"

//using constructor
let settings: ClientSettings = .localhost()


// settings with credentials
let settings: ClientSettings = .localhost(userCredentials: .init(username: "admin", 
                                                                   password: "changeit")

//settings with credentials with adding ssl file by path
let settings: ClientSettings = .localhost(userCredentials: .init(username: "admin", 
                                                                            password: "changeit"), 
                                                                 trustRoots: .file("...filePath..."))

//or add ssl file with bundle
let settings: ClientSettings = .localhost(userCredentials: .init(username: "admin", 
                                                                 password: "changeit"), 
                                                                 trustRoots: .fileInBundle(forResource: "ca", 
                                                                                           withExtension: "crt", 
                                                                                           inBundle: .main))
```

### Appending Event

`Version: 1.0.0`

```swift
// Import packages of KurrentDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Create the data array of events.
let events:[EventData] = [
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1164")!, eventType: "ItemAdded", payload: ["Description": "Xbox One S 1TB (Console)"]),
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1174")!, eventType: "ItemAdded", payload: "Gears of War 4")
        ]

// Create an identifier of stream
let streamIdentifier = StreamIdentifier(name: "stream_for_testing")

// Build a streams client.
let streams = Streams(settings: settings)

// Append two events with one response
let appendResponse = try await streams.append(to: streamIdentifier, events: events)
print("The latest revision of events appended:", appendResponse.currentRevision!)
```

`Version: 0.6.x`

```swift
// Import packages of EventStoreDB.
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a streams client.
let client = Streams(settings: settings)

// Create the data array of events.
let events:[EventData] = [
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1164")!, eventType: "ItemAdded", payload: ["Description": "Xbox One S 1TB (Console)"]),
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1174")!, eventType: "ItemAdded", payload: "Gears of War 4")
        ]

//let streamIdentifier = StreamIdentifier(name: "stream_for_testing")
let client = EventStoreDBClient(settings: settings)

let appendResponse = try await client.appendStream(to: streamIdentifier, events: events) { options in
    options.revision(expected: .any)
}

```

### Read Event

`Version: 1.0.0`

```swift
// Import packages of KurrentDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Create an identifier of stream.
let streamIdentifier = StreamIdentifier(name: "stream_for_testing")

// Build a streams client.
let streams = Streams(settings: settings)

// Read events from stream.
let readResponses = try await streams.read(streamIdentifier, cursor: .start)

// loop it.
for try await response in readResponses {
    //handle response
}
```

`Version: 0.6.x`

```swift
// Import packages of EventStoreDB.
import EventStoreDB

// Using a client setting to `EventStoreDBClient` by default.
let settings: ClientSettings = .localhost()

//prepare an identifier for a stream by a name.
let streamIdentifier = StreamIdentifier(name: "stream_for_testing")

//Check the event is appended into testing stream.
let client = try EventStoreDBClient(settings: settings)
let readResponses = try client.readStream(to: streamIdentifier, cursor: .end) { options in
    options.set(uuidOption: .string)
        .countBy(limit: 1)
}

for await response in readResponses {
    //handle response
}
```

### PersistentSubscriptions
#### Create

`Version: 1.0.0`

```swift
// Import packages of KurrentDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let persistentSubscriptions = PersistentSubscriptions(settings: settings)

// Create it to specified identifier of streams. 
try await persistentSubscriptions.createToStream(streamIdentifier: streamIdentifier, groupName: "mytest")

```

`Version: 0.6.x`

```swift
// Import packages of EventStoreDB.
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

let streamName = "stream_for_testing"

let client = try EventStoreDBClient(settings: settings)
try await client.createPersistentSubscription(streamName: streamName, groupName: "mytest", options: .init())

```

#### Subscribe

`Version: 1.0.0`

```swift
// Import packages of KurrentDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let persistentSubscriptions = PersistentSubscriptions(settings: settings)

// Subscribe to stream or all, and get a subscription.
let subscription = try await persistentSubscriptions.subscribe(.specified(streamIdentifier), groupName: "mytest")

// Loop all results by subscription.events
for try await result in subscription.events {
    //handle result
    // ...
    
    // ack the readEvent if succeed
    try await subscription.ack(readEvents: result.event)
    // else nack thr readEvent if not succeed.
    // try await subscription.nack(readEvents: result.event, action: .park, reason: "It's failed.")
}

```

`Version: 0.6.x`

```swift
// Import packages of EventStoreDB.
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

let streamName = "stream_for_testing"

let client = try EventStoreDBClient(settings: settings)

let subscription = try await client.subscribePersistentSubscriptionTo(.specified(streamName), groupName: "mytest")

for try await result in subscription {
    // handle result
    
    // ack the readEvent if succeed 
    try await subscription.ack(readEvents: result.event)
    // else nack thr readEvent if not succeed.
    try await subscription.nack(readEvents: result.event, action: .park, reason: "It's failed.")
}
```
