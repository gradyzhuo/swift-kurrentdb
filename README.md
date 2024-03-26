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

#### Appending Event

```swift
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.

try EventStoreDB.using(settings: .parse(connectionString: "esdb://admin:changeit@localhost:2113"))

// convenience 
//try EventStoreDB.using(settings: "esdb://admin:changeit@localhost:2113".parse())

// using string literal 
//try EventStoreDB.using(settings: "esdb://admin:changeit@localhost:2113")




//or 
//try EventStoreDB.using(settings: .localhost(userCredentials: .init(username: "admin", password: "changeit"))

//or add ssl file by path
// try EventStoreDB.using(settings: .localhost(userCredentials: .init(username: "admin", password: "changeit"), trustRoots: .file("...filePath...")))

//or add ssl file with bundle
// try EventStoreDB.using(settings: .localhost(userCredentials: .init(username: "admin", password: "changeit"), trustRoots: .fileInBundle(forResource: "ca", withExtension: "crt", inBundle: .main)))



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


let client = try EventStoreDB.Client()

let appendResponse = try await client.appendTo(streamName: streamName, events: .init(eventType: "AccountCreated", payload: content)) { options in
    options.expectedRevision(.any)
}

```

#### Read Event

```swift
//...continue after appending

let rev = appendResponse.current.revision

//Check the event is appended into testing stream.
let readResponses = try client.read(streamName: streamName, cursor: .end) { options in
    options.set(uuidOption: .string)
        .countBy(limit: 1)
}

let results = try await readResponses
```
