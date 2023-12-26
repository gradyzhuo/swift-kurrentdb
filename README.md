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
  dependencies: [.product(name: "EventStoreDB", package: "eventstore-swift")]
]
```

### Examples

#### Appending Event

```swift
import EventStoreDB


```
