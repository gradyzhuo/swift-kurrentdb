# PersistentSubscriptionTarget design

The target-based architecture for persistent subscriptions, providing compile-time type safety through protocol composition.

## Overview

The Persistent Subscriptions API uses a target-based design pattern, consistent with ``StreamsTarget``, ``UsersTarget``, ``ProjectionsTarget``, and ``OperationsTarget``. Each target type determines the scope and available operations at compile time.

## Protocol hierarchy

```
PersistentSubscriptionTarget (Protocol)
├── PersistentSubscription.Specified (Struct)
├── PersistentSubscription.AllStream (Struct)
├── PersistentSubscription.All (Struct)
└── PersistentSubscription.AnyTarget (Struct)
```

## Target types

Each target type represents a different scope for persistent subscription operations:

| Target | Properties | Purpose | Operations |
|--------|-----------|---------|------------|
| ``PersistentSubscription/Specified`` | `identifier`, `group` | Manage a subscription group on a specific stream | `create()`, `update()`, `delete()`, `subscribe()`, `getInfo()`, `replayParked()` |
| ``PersistentSubscription/AllStream`` | `group` | Manage a subscription group on the `$all` stream | `create()`, `update()`, `delete()`, `subscribe()`, `getInfo()`, `replayParked()` |
| ``PersistentSubscription/All`` | — | Cluster-wide listing and subsystem control | `list(for:)`, `restartSubsystem()` |
| ``PersistentSubscription/AnyTarget`` | — | Generic target for unspecified contexts | — |

## Design decisions

### Why separate Specified and AllStream?

Persistent subscriptions on specific streams and the `$all` stream have fundamentally different characteristics:

1. **Specified** — Targets a single stream by `StreamIdentifier` and a `group` name. Uses stream revisions for position tracking. Configuration options are stream-specific.
2. **AllStream** — Targets the global `$all` stream with a `group` name. Uses commit positions instead of revisions. Supports additional options like event type filtering.

Each target holds the state needed for its scope: `Specified` stores both the stream identifier and group name, while `AllStream` only stores the group name (since the stream is implicitly `$all`).

### Why a separate All target?

``PersistentSubscription/All`` represents the cluster-wide view of persistent subscriptions. It does not target any specific subscription group — instead, it provides system-level operations:

- **Listing** — Query subscription groups across all streams, a specific stream, or `$all`
- **Subsystem restart** — Restart the entire persistent subscription subsystem

These operations don't require a stream identifier or group name, so they are isolated from the stream-scoped targets.

### Relationship with Streams

Unlike other target-based APIs (Users, Operations, Projections), persistent subscriptions are accessed **through** the ``Streams`` API rather than directly from the client. This reflects the domain model: persistent subscriptions are always associated with a stream (either a specific stream or `$all`).

```swift
// Persistent subscriptions are created via Streams
client.streams(of: .specified("orders"))
    .persistentSubscriptions(group: "workers")     // → PersistentSubscriptions<Specified>

client.streams(of: .all)
    .persistentSubscriptions(group: "audit")       // → PersistentSubscriptions<AllStream>
```

This design leverages the existing ``StreamsTarget`` infrastructure to determine whether the subscription is on a specific stream or `$all`, then creates the appropriate ``PersistentSubscriptionTarget`` type.

## Static factory methods

Targets are created via `where Self ==` constrained extensions on ``PersistentSubscriptionTarget``:

```swift
// Specific stream subscription
PersistentSubscriptionTarget.specified("orders", group: "workers")
PersistentSubscriptionTarget.specified(streamIdentifier, group: "workers")

// All streams (cluster-wide operations)
PersistentSubscriptionTarget.all
```

In practice, targets are most commonly created through the ``Streams`` interface:

```swift
// Through Streams (recommended)
client.streams(of: .specified("orders")).persistentSubscriptions(group: "workers")
client.streams(of: .all).persistentSubscriptions(group: "audit")
```

## Type safety

The target-based design provides compile-time guarantees that prevent invalid operation combinations:

```swift
// ✓ Correct: Create subscription on a specific stream
let specified = client.streams(of: .specified("orders"))
    .persistentSubscriptions(group: "workers")
try await specified.create()
try await specified.subscribe()
try await specified.delete()

// ✓ Correct: Create subscription on $all
let allStream = client.streams(of: .all)
    .persistentSubscriptions(group: "audit")
try await allStream.create()
try await allStream.subscribe()

// ✓ Correct: List all subscriptions cluster-wide
let all = client.persistentSubscriptions  // PersistentSubscriptions<All>
try await all.list(for: .allSubscriptions)
try await all.restartSubsystem()

// ✗ Compile error: Cannot list from a specific subscription target
try await specified.list(for: .allSubscriptions)

// ✗ Compile error: Cannot restart subsystem from a stream-scoped target
try await specified.restartSubsystem()

// ✗ Compile error: Cannot create/subscribe from All target
try await all.create()
try await all.subscribe()
```

## Subscription class

The ``PersistentSubscriptions/Subscription`` class is returned when subscribing to a persistent subscription group. It provides:

- **`events`** — An `AsyncThrowingStream` of ``PersistentSubscription/EventResult`` for consuming events
- **`ack(readEvents:)`** — Acknowledge successful event processing
- **`nack(readEvents:action:reason:)`** — Negatively acknowledge events with retry, park, or skip actions
- **`subscriptionId`** — The server-assigned subscription identifier

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget | PersistentSubscriptionTarget |
|---------|--------------|-------------|-------------------|------------------|------------------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` | `PersistentSubscriptionTarget` |
| Specified Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` | `PersistentSubscription.Specified` |
| System Target | `AllStreams` | — | `AnyProjectionsTarget` | `SystemOperations` | `PersistentSubscription.All` |
| All-Stream Target | — | — | — | — | `PersistentSubscription.AllStream` |
| Service Actor | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` | `PersistentSubscriptions<Target>` |
| Access Pattern | `client.streams(of:)` | `client.users` / `client.user(_:)` | `client.projections(of:)` | `client.operations(of:)` | `client.streams(of:).persistentSubscriptions(group:)` |

## File structure

```
Sources/KurrentDB/PersistentSubscriptions/
├── PersistentSubscriptionTarget.swift             # Base protocol + target types + factory methods
├── PersistentSubscriptions.swift                   # Generic PersistentSubscriptions<Target> actor
├── PersistentSubscriptions.Subscription.swift      # Subscription class (events, ack, nack)
├── PersistentSubscriptions.ReadResponse.swift      # Read response types
├── PersistentSubscriptions.StreamSelection.swift   # Stream selection enum
├── PersistentSubscriptions.ReplayParkedOptions.swift
├── PersistentSubscriptionStreamSelection.swift
├── PersistentSubscriptionsSettingsBuildable.swift   # Settings builder protocol
├── Additions/
│   ├── EventStore_Client_PersistentSubscriptions+Additions.swift
│   ├── ReadEvent+Additions.swift
│   └── PersistentSubscriptions+Convenience.swift
└── Usecase/
    ├── PersistentSubscriptions.Ack.swift            # Acknowledge events
    ├── PersistentSubscriptions.Nack.swift           # Negative acknowledge events
    ├── PersistentSubscriptions.RestartSubsystem.swift
    ├── All/
    │   └── PersistentSubscriptions.ListForAll.swift # List all subscriptions
    ├── Specified/                                   # Specific stream operations
    │   ├── PersistentSubscriptions.SpecifiedStream.Create.swift
    │   ├── PersistentSubscriptions.SpecifiedStream.Read.swift
    │   ├── PersistentSubscriptions.SpecifiedStream.Update.swift
    │   ├── PersistentSubscriptions.SpecifiedStream.Delete.swift
    │   ├── PersistentSubscriptions.SpecifiedStream.GetInfo.swift
    │   ├── PersistentSubscriptions.SpecifiedStream.List.swift
    │   └── PersistentSubscriptions.SpecifiedStream.ReplayParked.swift
    └── AllStream/                                   # $all stream operations
        ├── PersistentSubscriptions.AllStream.Create.swift
        ├── PersistentSubscriptions.AllStream.Read.swift
        ├── PersistentSubscriptions.AllStream.Update.swift
        ├── PersistentSubscriptions.AllStream.Delete.swift
        ├── PersistentSubscriptions.AllStream.GetInfo.swift
        ├── PersistentSubscriptions.AllStream.List.swift
        └── PersistentSubscriptions.AllStream.ReplayParked.swift
```
