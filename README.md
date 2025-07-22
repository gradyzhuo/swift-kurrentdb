[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FKurrentDB-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FKurrentDB-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift)
[![Swift-build-testing](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/offsky-studio/KurrentDB-Swift/actions/workflows/swift-build-testing.yml)


# KurrentDB 
This is unofficial [Kurrent](https://www.kurrent.io/) (formerly: EventStore) Database [gRPC](https://github.com/grpc/grpc-swift.git) Client SDK, developing in [Swift language](https://www.swift.org/)


## Getting the library

### Swift Package Manager

The Swift Package Manager is the preferred way to get KurrentDB. Simply add the package dependency to your Package.swift:

```swift
dependencies: [
  .package(url: "https://github.com/gradyzhuo/KurrentDB-Swift.git", from: "1.0.0")
]
```
...and depend on "KurrentDB" in the necessary targets:

```swift
.target(
  name: ...,
  dependencies: [.product(name: "KurrentDB", package: "KurrentDB-Swift")]
]
```

## Examples

### The library name to import.

```swift
import KurrentDB
```


### ClientSettings

```swift
// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .parse(connectionString: "kurrent://localhost:2113")

// convenience 
let settings: ClientSettings = "kurrent://localhost:2113".parse()

// using string literal 
let settings: ClientSettings = "kurrent://localhost:2113"

//using constructor
let settings: ClientSettings = .localhost()
```

### ClientSettings with credentials authentication.
```swift
// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .parse(connectionString: "kurrent://admin:changeit@localhost:2113")

// convenience 
let settings: ClientSettings = "kurrent://admin:changeit@localhost:2113".parse()

// using string literal 
let settings: ClientSettings = "kurrent://admin:changeit@localhost:2113"

//using constructor
let settings: ClientSettings = .localhost()
                               .authenticated(.credentials(username: "admin", password: "changeit"))
```

### ClientSettings with CA file.
```swift
// parse from connection string
let caPath = "the path of ca file..."
let settings: ClientSettings = "kurrent://admin:changeit@localhost:2113?tls=true&tlsCaFile=\(caPath)".parse()

//or construct in coding.
//settings with credentials with adding ssl file by path
let settings: ClientSettings = .localhost()
                               .secure(true) //required
                               .cerificate(path: caPath!)
                               .authenticated(.credentials(username: "admin", password: "changeit"))

//or add ssl file with bundle
let settings: ClientSettings = .localhost()
                               .secure(true) //required
                               .cerificate(source: .crtInBundle("ca")!)
                               .authenticated(.credentials(username: "admin", password: "changeit"))
```

### Appending Event

```swift
// Import packages of KurrentDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Create the data array of events.
let events:[EventData] = [
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1164")!, eventType: "ItemAdded", model: ["Description": "Xbox One S 1TB (Console)"]),
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1174")!, eventType: "ItemAdded", model: "Gears of War 4")]

// Append two events with one response
let client = KurrentDBClient(settings: .localhost())
try await client.appendStream("stream_for_testing", events: events){
    $0.revision(expected: .any)
}
```

### Read Event

```swift
// Import packages of EventStoreDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Read responses of event from specified stream.
let responses = try await client.readStream("stream_for_testing"){
    $0.backward().startFrom(revision: .start)
}

// loop it.
for try await response in responses {
    //handle response
    if let readEvent = try response.event {
        //handle event
    }
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

// Create it to specified identifier of stream
try await client.createPersistentSubscription(stream: streamIdentifier, groupName: groupName)
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
let subscription = try await client.subscribePersistentSubscription(stream: streamIdentifier, groupName: groupName)

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
