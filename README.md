[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fgradyzhuo%2FEventStoreDB-Swift%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/gradyzhuo/EventStoreDB-Swift)

[![Swift-build-testing](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml/badge.svg)](https://github.com/gradyzhuo/EventStoreDB-Swift/actions/workflows/swift-build-testing.yml)
[![codecov](https://codecov.io/github/gradyzhuo/EventStoreDB-Swift/graph/badge.svg?token=1NDTE6YT73)](https://codecov.io/github/gradyzhuo/EventStoreDB-Swift)



# KurrentDB(original: EventStoreDB)
[Kurrent](https://www.eventstore.com) Database [gRPC](https://github.com/grpc/grpc-swift.git) Client SDK in Swift.

### Implementation Status
- Client Settings
    ☑️ ConnectionString parsed
    ☑️ Endpoint (ip, port)
    ☑️ UserCredentials ( username, password )
    🔲 Gossip ClusterMode 
    
- Stream
    ☑️ Append
    ☑️ Read
    ☑️ Metadata { set , get }
    ☑️ Subscribe Specified Stream
    ☑️ Subscribe All Stream

- Projection
    ☑️ Create
    ☑️ Update
    ☑️ Result 
    ☑️ Delete
    ☑️ Enable
    ☑️ Disable
    ☑️ Enable
    ☑️ State
    ☑️ Statistics
    ☑️ Reset
    ☑️ RestartSubsystem
    
- PersistentSubscriptions
    ☑️ Create
    ☑️ Delete
    ☑️ GetInfo
    ☑️ List
    ☑️ Read
    ☑️ ReplayParked
    ☑️ RestartSubsystem
    ☑️ Subscribe
    ☑️ Update

- User
    ☑️ Create
    ☑️ Details


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

#### Appending Event

```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()


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

let streamIdentifier = Stream.Identifier(name: "stream_for_testing")
let client = try EventStoreDB.Client(settings: settings)

let appendResponse = try await client.appendStream(to: streamIdentifier, events: events) { options in
    options.expectedRevision(.any)
}

```

#### Read Event

```swift
import EventStoreDB

// Using a client setting to `EventStoreDBClient` by default.
let settings: ClientSettings = .localhost()

//prepare an identifier for a stream by a name.
let streamIdentifier = Stream.Identifier(name: "stream_for_testing")

//Check the event is appended into testing stream.
let client = try EventStoreDB.Client(settings: settings)
let readResponses = try client.readStream(to: streamIdentifier, cursor: .end) { options in
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
let settings: ClientSettings = .localhost()

let streamName = "stream_for_testing"

let client = try EventStoreDB.Client(settings: settings)
try await client.createPersistentSubscription(streamName: streamName, groupName: "mytest", options: .init())

```

##### Subscribe
```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

let streamName = "stream_for_testing"

let client = try EventStoreDB.Client(settings: settings)

let subscription = try await client.subscribePersistentSubscriptionTo(.specified(streamName), groupName: "mytest")

for try await result in subscription {
    // handle result
    
    // ack the readEvent if succeed 
    try await subscription.ack(readEvents: result.event)
    // else nack thr readEvent if not succeed.
    try await subscription.nack(readEvents: result.event, action: .park, reason: "It's failed.")
}
```
