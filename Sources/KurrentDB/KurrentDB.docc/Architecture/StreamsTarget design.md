# StreamsTarget design

The target-based architecture for stream operations, providing compile-time type safety through protocol composition.

## Overview

The Streams API uses a target-based design pattern, consistent with ``UsersTarget``, ``ProjectionsTarget``, and ``OperationsTarget``. Each target type determines the scope and available operations at compile time.

## Protocol hierarchy

```
StreamsTarget (Protocol)
├── SpecifiedStreamTarget (Protocol)
│   ├── SpecifiedStream (Struct)
│   ├── ProjectionStream (Struct)
│   └── String (Extension)
├── AllStreamsTarget (Struct)
├── MultiStreamsTarget (Struct)
└── AnyStreamTarget (Struct)
```

## Target types

Each target type represents a different scope for stream operations:

| Target | Purpose | Operations |
|--------|---------|------------|
| ``SpecifiedStream`` | A single named stream | `append(events:configure:)`, `read(configure:)`, `subscribe(configure:)`, `delete(configure:)`, `tombstone(configure:)`, `getMetadata()`, `setMetadata(metadata:expectedRevision:)` |
| ``AllStreamsTarget`` | The global `$all` stream | `read(configure:)`, `subscribe(configure:)` |
| ``MultiStreamsTarget`` | Writes across several streams | `append(events:)`, `appendRecords(events:checks:)`, `batchAppend(events:)` |
| ``ProjectionStream`` | Streams produced by system projections | Everything ``SpecifiedStreamTarget`` offers |

## Design decisions

### Why separate SpecifiedStream and AllStreamsTarget?

Stream operations have fundamentally different scopes:

1. **SpecifiedStream** — A single named stream. Supports the full range of operations: append, read, subscribe, delete, tombstone and metadata.
2. **AllStreamsTarget** — The global `$all` stream containing every event in the store. Supports only read and subscribe — you cannot append to or delete `$all`.

This separation means you cannot accidentally append to or delete `$all`.

### Why a separate MultiStreamsTarget?

Writing to several streams in one call has its own guarantees and server requirements: an atomic multi-stream append (KurrentDB 25.1+), an atomic append with cross-stream consistency checks (`appendRecords`, KurrentDB 26.1+), and a pipelined, non-atomic `batchAppend`. ``MultiStreamsTarget`` keeps these apart from single-stream operations, so the intent is explicit.

### Why does String conform to SpecifiedStreamTarget?

For convenience, `String` conforms to ``SpecifiedStreamTarget``, so stream names can be used directly where a stream target is expected. ``SpecifiedStream`` also conforms to `ExpressibleByStringLiteral` for the same reason.

## Static factory methods

Each target has a static factory method on ``StreamsTarget`` via `where Self ==` extensions:

```swift
client.streams(of: .specified("orders"))            // SpecifiedStream
client.streams(of: .all)                            // AllStreamsTarget
client.streams(of: .multiple)                       // MultiStreamsTarget
client.streams(of: .byEventType("OrderCreated"))    // ProjectionStream
client.streams(of: .byStream(prefix: "order"))      // ProjectionStream
```

The most common ones also have shorthands on ``KurrentDBClient``:

```swift
client.streams(specified: "orders")   // client.streams(of: .specified("orders"))
client.allStreams                     // client.streams(of: .all)
client.multiStreams                   // client.streams(of: .multiple)
```

## Type safety

The target-based design turns invalid combinations into compile errors:

```swift
// ✓ Append to a specific stream
try await client.streams(of: .specified("orders"))
    .append(events: [eventData])

// ✓ Read from $all
let responses = try await client.streams(of: .all)
    .read { $0.direction = .forward }

// ✓ Append to several streams at once
try await client.streams(of: .multiple)
    .append(events: [StreamEvent(stream: "orders", records: [record])])
```

<!-- snippet:skip -->
```swift
// ✗ Compile error: cannot append to $all
try await client.streams(of: .all).append(events: [eventData])

// ✗ Compile error: cannot delete $all
try await client.streams(of: .all).delete()

// ✗ Compile error: cannot read from MultiStreamsTarget
try await client.streams(of: .multiple).read()
```

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget |
|---------|--------------|-------------|-------------------|------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` |
| Creation Target | — | `AllUsersTarget` | `SpecifiedContinuousProjectionTarget`, `OneTimeProjectionTarget`, `SpecifiedTransientProjectionTarget` | `ScavengeOperations` |
| Control Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` |
| System Target | `AllStreamsTarget` | — | `AnyProjectionsTarget` | `SystemOperations` |
| Batch Target | `MultiStreamsTarget` | — | — | — |
| Service | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` |

## File structure

```
Sources/KurrentDB/Streams/
├── KurrentDBClient+Streams.swift          # streams(of:), streams(specified:), allStreams, multiStreams
├── Streams.swift                          # Generic Streams<Target> service
├── Streams.ReadResponse.swift             # Read response types
├── Streams.Subscription.swift             # Subscription types
├── StreamFilter+Build.swift               # StreamFilter → gRPC request mapping
├── Additions/
│   └── StreamIdentifier+Additions.swift
├── API/                                   # Operations, one file per target constraint
│   ├── Streams+SpecifiedStreamTarget.swift
│   ├── Streams+AllStreamsTarget.swift
│   └── Streams+ProjectionStream.swift     # ProjectionStream and MultiStreamsTarget
├── Target/                                # StreamsTarget and every target type
└── Usecase/
    ├── Specified/                         # Single- and multi-stream operations
    │   ├── Streams.Append.swift
    │   ├── Streams.AppendRecords.swift
    │   ├── Streams.AppendSession.swift
    │   ├── Streams.BatchAppend.swift
    │   ├── Streams.Read.swift
    │   ├── Streams.Subscribe.swift
    │   ├── Streams.Delete.swift
    │   └── Streams.Tombstone.swift
    └── All/                               # $all stream operations
        ├── Streams.ReadAll.swift
        └── Streams.SubscribeAll.swift
```
