# EventStoreDB-Swift
[EventStore](https://www.eventstore.com) [gRPC](https://github.com/grpc/grpc-swift.git) Client SDK in Swift.


Getting the gRPC library

Swift Package Manager

The Swift Package Manager is the preferred way to get gRPC Swift. Simply add the package dependency to your Package.swift:

```
dependencies: [
  .package(url: "https://github.com/gradyzhuo/eventstoredb-swift.git", branch: "main")
]
```
...and depend on "GRPC" in the necessary targets:

```
.target(
  name: ...,
  dependencies: [.product(name: "EventStoreDB", package: "eventstore-swift")]
]
```
