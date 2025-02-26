[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)
[![Swift-build-testing](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml)



# KurrentDB 
This is unofficial [Kurrent](https://www.kurrent.io/) (formerly: EventStore) Database [gRPC](https://github.com/grpc/grpc-swift.git) Client SDK, developing in [Swift language](https://www.swift.org/)

Kurrent is the first and only event-native data platform. It is built to store and stream data as events for use in downstream use cases such as advanced analytics, microservices and AI/ML initiatives.

Swift is a general-purpose programming language that’s approachable for newcomers and powerful for experts.
It is fast, modern, safe, and a joy to write.

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
|Disable|✅|
|Enable|✅|
|Update|✅|
|ChangePassword|✅|
|ResetPassword|✅|


## Getting the library

### Swift Package Manager

The Swift Package Manager is the preferred way to get EventStoreDB. Simply add the package dependency to your Package.swift:

```swift
dependencies: [
  .package(url: "https://github.com/gradyzhuo/eventstoredb-swift.git", from: "1.0.0")
]
```
...and depend on "EventStoreDB" in the necessary targets:

```swift
.target(
  name: ...,
  dependencies: [.product(name: "KurrentDB", package: "eventstoredb-swift")]
]
```

## Examples

### The library name to import.

```
import KurrentDB
```


### ClientSettings

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
let client = KurrentDBClient(settings: .localhost())

// Append two events with one response
let appendResponse = try await client.appendStream(to: streamIdentifier, events: events) { options in
    options.revision(expected: .any)
}

print("The latest revision of events appended:", appendResponse.currentRevision!)
```

### Read Event

```swift
// Import packages of EventStoreDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Create an identifier of stream.
let streamIdentifier = StreamIdentifier(name: "stream_for_testing")

// Build a streams client.
let client = KurrentDBClient(settings: settings)

// Read events from stream.
let readResponses = try await client.readStream(to: streamIdentifier, cursor: .start) { options in
    options.set(resolveLinks: true)
}

// loop it.
for try await response in readResponses {
    //handle response
}
```

### PersistentSubscriptions
#### Create

```swift
// Import packages of EventStoreDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let client = KurrentDBClient(settings: settings)

// the stream identifier to subscribe.
let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

// the group of subscription
let groupName = "myGroupTest"

// Create it to specified identifier of streams.
try await client.createPersistentSubscription(to: streamIdentifier, groupName: groupName)
```

#### Subscribe

```swift
// Import packages of EventStoreDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let client = KurrentDBClient(settings: settings)

// the stream identifier to subscribe.
let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

// the group of subscription
let groupName = "myGroupTest"


// Subscribe to stream or all, and get a subscription.
let subscription = try await client.subscribePersistentSubscription(to: .specified(streamIdentifier), groupName: groupName)

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
