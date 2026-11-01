# Migrating from 2.x to 3.0

Learn what changes when you move a 2.x program to 3.0: reads deliver events as you iterate, deprecated API is gone, and subscriptions can deliver the server's notifications next to the events.

## Overview

A 2.x program that compiles against 3.0 behaves differently only at the sites listed on this page. Each change below shows the 2.x code and the 3.0 code and says what to do. Anything not listed here keeps working as in 2.6.1 — see "What did not change" at the end.

## Before you start

Raise the requirement in your `Package.swift`:

<!-- snippet:skip -->
```swift
dependencies: [
    .package(url: "https://github.com/gradyzhuo/swift-kurrentdb.git", from: "3.0.0")
]
```

Then check four things before you build.

<!-- S17 -->
- **Packages that pin swift-kurrentdb.** If a package you depend on pins swift-kurrentdb (swift-ddd-kit does), update it first or your resolution keeps 2.x.
- **Dependency floors.** 3.0 requires swift-protobuf 1.37.0 or later and grpc-swift-2 2.3.0 or later. If your package, or one you depend on, caps either below those versions (`exact:`, `.upToNextMinor(from:)` or a range that ends below them), resolution fails: lift the cap, or update that package or ask its maintainer to.
- **On 2.6.0 or earlier.** Upgrade to 2.6.1 first and run your tests there. 2.6.1 changed three behaviours that 3.0 keeps, all listed under 2.6 in What's new: a record's custom metadata reaches the server (and metadata that is not a JSON object now throws), `multiStreams.append` checks each event's expected revision, and a subscription to a tombstoned stream ends with `resourceDeleted`. This page compares 3.0 with 2.6.1.
- **`KurrentDB_V1`.** 3.0 has no `KurrentDB_V1` module. If you still `import KurrentDB_V1`, migrate on 2.6 first: pin `from: "2.6.1"`, follow [the 2.6 migration guide](https://gradyzhuo.github.io/swift-kurrentdb/2.6/documentation/kurrentdb/migration-guide), then delete the import and come back here. Before you delete it, sort every `client.shutdown()`: with `KurrentDB_V1` imported it shuts the **server** down, and once the import is gone the same line closes only the client, still compiling. Rewrite each one that means the server as `try await client.operations(of: .system).shutdown()`; leave each one that means the client as it is until the import is gone. The box at the top of <doc:Migration-guide> lists the uses no warning points at, such as a protocol of yours that requires `func shutdown() async throws`.

## read() is lazy

## Removed and renamed API

## Subscription notifications

## What did not change
