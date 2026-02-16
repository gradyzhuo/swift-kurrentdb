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
├── AllStreams (Struct)
├── MultiStreams (Struct)
└── AnyStreamTarget (Struct)
```

## Target types

Each target type represents a different scope for stream operations:

| Target | Purpose | Operations |
|--------|---------|------------|
| ``SpecifiedStream`` | Operates on a specific named stream | `append(events:)`, `read(configure:)`, `subscribe(configure:)`, `delete(configure:)`, `tombstone(configure:)` |
| ``AllStreams`` | Operates on the global `$all` stream | `read(configure:)`, `subscribe(configure:)` |
| ``MultiStreams`` | Batch operations across multiple streams | `append(events:)` (batch) |
| ``ProjectionStream`` | System projection-generated streams | Inherits from ``SpecifiedStreamTarget`` |

## Design decisions

### Why separate SpecifiedStream and AllStreams?

Stream operations have fundamentally different scopes:

1. **SpecifiedStream** — Operates on a single named stream. Supports the full range of operations: append, read, subscribe, delete, and tombstone.
2. **AllStreams** — Represents the global `$all` stream containing all events across all streams. Only supports read and subscribe operations — you cannot append to or delete `$all`.

This separation ensures you cannot accidentally append events to the `$all` stream or delete it, which would be invalid operations.

### Why a separate MultiStreams target?

KurrentDB 25.1+ supports batch append across multiple streams in a single operation. ``MultiStreams`` isolates this capability from single-stream operations, making the API intent explicit.

### Why does String conform to SpecifiedStreamTarget?

For convenience, `String` conforms to ``SpecifiedStreamTarget``, allowing stream names to be used directly where a stream identifier is expected. ``SpecifiedStream`` also conforms to `ExpressibleByStringLiteral` for the same reason.

## Static factory methods

Each target has a static factory method on ``StreamsTarget`` via `where Self ==` extensions:

```swift
client.streams(of: .specified("orders"))            // SpecifiedStream
client.streams(of: .all)                            // AllStreams
client.streams(of: .multiple)                       // MultiStreams
client.streams(of: .byEventType("OrderCreated"))    // ProjectionStream
client.streams(of: .byStream(prefix: "order"))      // ProjectionStream
```

## Type safety

The target-based design provides compile-time guarantees that prevent invalid operation combinations:

```swift
// ✓ Correct: Append to a specific stream
try await client.streams(of: .specified("orders"))
    .append(events: [...])

// ✓ Correct: Read from $all
try await client.streams(of: .all)
    .read(configure: { $0.forward() })

// ✗ Compile error: Cannot append to $all
try await client.streams(of: .all).append(events: [...])

// ✗ Compile error: Cannot delete $all
try await client.streams(of: .all).delete()

// ✓ Correct: Batch append to multiple streams
try await client.streams(of: .multiple)
    .append(events: [...])

// ✗ Compile error: Cannot read from MultiStreams
try await client.streams(of: .multiple).read(configure: { $0.forward() })
```

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget |
|---------|--------------|-------------|-------------------|------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` |
| Creation Target | — | `AllUsersTarget` | `ContinuousTarget`, `OneTimeTarget`, `TransientTarget` | `ScavengeOperations` |
| Control Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` |
| System Target | `AllStreams` | — | `AnyProjectionsTarget` | `SystemOperations` |
| Batch Target | `MultiStreams` | — | — | — |
| Service Actor | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` |

## File structure

```
Sources/KurrentDB/Streams/
├── StreamsTarget.swift                    # Base protocol + all target types + factory methods
├── Streams.swift                          # Generic Streams<Target> actor
├── Streams.ReadResponse.swift             # Read response types
├── Streams.Subscription.swift             # Subscription types
├── Additions/
│   └── StreamIdentifier+Additions.swift   # StreamIdentifier extensions
└── Usecase/
    ├── Specified/                         # Single-stream operations
    │   ├── Streams.Append.swift
    │   ├── Streams.AppendSession.swift
    │   ├── Streams.Read.swift
    │   ├── Streams.Subscribe.swift
    │   ├── Streams.Delete.swift
    │   └── Streams.Tombstone.swift
    └── All/                               # $all stream operations
        ├── Streams.ReadAll.swift
        └── Streams.SubscribeAll.swift
```
