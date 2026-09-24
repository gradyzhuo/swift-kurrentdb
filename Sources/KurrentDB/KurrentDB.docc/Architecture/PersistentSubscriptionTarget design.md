# PersistentSubscriptionTarget design

The target-based architecture for persistent subscriptions, providing compile-time type safety through protocol composition.

## Overview

The Persistent Subscriptions API uses a target-based design pattern, consistent with ``StreamsTarget``, ``UsersTarget``, ``ProjectionsTarget``, and ``OperationsTarget``. Each target type determines the scope and available operations at compile time.

## Protocol hierarchy

```
PersistentSubscriptionTarget (Protocol)
├── SpecifiedPersistentSubscriptionTarget (Struct)
├── AllStreamPersistentSubscriptionTarget (Struct)
├── FilterStreamPersistentSubscriptionTarget (Struct)
├── AllPersistentSubscriptionTarget (Struct)
└── AnyPersistentSubscriptionTarget (Struct)
```

## Target types

Each target type represents a different scope for persistent subscription operations:

| Target | Properties | Purpose | Operations |
|--------|-----------|---------|------------|
| ``SpecifiedPersistentSubscriptionTarget`` | `identifier`, `group` | A subscription group on a specific stream | `create`, `update`, `delete`, `subscribe`, `getInfo`, `replayParked` |
| ``AllStreamPersistentSubscriptionTarget`` | `group` | A subscription group on the `$all` stream | `create`, `update`, `delete`, `subscribe`, `getInfo`, `replayParked` |
| ``FilterStreamPersistentSubscriptionTarget`` | stream name | Every group on one stream | `list` |
| ``AllPersistentSubscriptionTarget`` | — | Every group on the server, and the subsystem | `list`, `restartSubsystem` |
| ``AnyPersistentSubscriptionTarget`` | — | Generic target for unspecified contexts | — |

## Design decisions

### Why separate the specified and $all targets?

Groups on a specific stream and groups on `$all` differ in kind:

1. **SpecifiedPersistentSubscriptionTarget** — a single stream, identified by its ``StreamIdentifier``, plus a group name. Positions are stream revisions.
2. **AllStreamPersistentSubscriptionTarget** — the global `$all` stream plus a group name. Positions are commit positions, and groups can filter by stream name or event type.

Each target holds only the state its scope needs: the specified target stores the stream identifier and the group name; the `$all` target stores just the group name, because the stream is implicitly `$all`.

### Why separate listing targets?

Listing doesn't address a single group, so it has its own targets: ``FilterStreamPersistentSubscriptionTarget`` lists the groups on one stream, and ``AllPersistentSubscriptionTarget`` lists every group and restarts the subsystem. Neither needs a group name, and neither can create or subscribe.

### Relationship with Streams

Persistent subscriptions are always attached to a stream — a specific one or `$all` — so besides the client's own accessors, a ``Streams`` value can hand out the persistent subscriptions for its stream:

```swift
client.streams(specified: "orders")
    .persistentSubscriptions(group: "workers")     // → PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>

client.allStreams
    .persistentSubscriptions(group: "audit")       // → PersistentSubscriptions<AllStreamPersistentSubscriptionTarget>
```

Credentials set with `authenticated(_:)` on the ``Streams`` value carry over.

## Static factory methods

Targets are created via `where Self ==` constrained extensions on ``PersistentSubscriptionTarget``:

```swift
client.persistentSubscriptions(of: .specified(stream: "orders", group: "workers"))
client.persistentSubscriptions(of: .allStreams(group: "audit"))
client.persistentSubscriptions(of: .filter(stream: "orders"))
client.persistentSubscriptions(of: .all)
```

The client also has shorthands for each:

```swift
client.persistentSubscriptions(stream: "orders", group: "workers")
client.persistentSubscriptions(filterGroup: "audit")
client.persistentSubscriptions(filterStream: "orders")
client.allPersistentSubscriptions
```

## Type safety

The target-based design turns invalid combinations into compile errors:

```swift
// ✓ Manage and consume a group on a specific stream
let specified = client.persistentSubscriptions(stream: "orders", group: "workers")
try await specified.create()
let subscription = try await specified.subscribe()
try await specified.delete()

// ✓ Manage and consume a group on $all
let allStream = client.persistentSubscriptions(filterGroup: "audit")
try await allStream.create()
let allSubscription = try await allStream.subscribe()

// ✓ List every group and restart the subsystem
let all = client.allPersistentSubscriptions
let groups = try await all.list()
try await all.restartSubsystem()
```

<!-- snippet:skip -->
```swift
let specified = client.persistentSubscriptions(stream: "orders", group: "workers")
let all = client.allPersistentSubscriptions

// ✗ Compile error: a group target can't list every group
try await specified.list()

// ✗ Compile error: a stream-scoped target can't restart the subsystem
try await specified.restartSubsystem()

// ✗ Compile error: the server-wide target can't create or subscribe
try await all.create()
try await all.subscribe()
```

## Subscription class

``PersistentSubscriptions/Subscription`` is returned when you subscribe to a group. It provides:

- **`events`** — An `AsyncThrowingStream` of ``PersistentSubscription/EventResult`` values to consume
- **`ack(readEvents:)`** — Acknowledge successfully processed events
- **`nack(readEvents:action:reason:)`** — Reject events with a retry, park, skip or stop action
- **`subscriptionId`** — The server-assigned subscription identifier
- **`lastRevision`** / **`lastPosition`** — Where the last received event was, for resuming after a drop

The subscription's connection closes once nothing references the subscription or its `events` stream.

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget | PersistentSubscriptionTarget |
|---------|--------------|-------------|-------------------|------------------|------------------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` | `PersistentSubscriptionTarget` |
| Specified Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` | `SpecifiedPersistentSubscriptionTarget` |
| System Target | `AllStreamsTarget` | — | `AnyProjectionsTarget` | `SystemOperations` | `AllPersistentSubscriptionTarget` |
| All-Stream Target | — | — | — | — | `AllStreamPersistentSubscriptionTarget` |
| Service | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` | `PersistentSubscriptions<Target>` |
| Access Pattern | `client.streams(of:)` | `client.users` / `client.user(_:)` | `client.projections(of:)` | `client.operations(of:)` | `client.persistentSubscriptions(of:)` |

## File structure

```
Sources/KurrentDB/PersistentSubscriptions/
├── KurrentDBClient+PersistentSubscriptions.swift   # Client accessors
├── PersistentSubscriptions.swift                   # Generic PersistentSubscriptions<Target> service
├── PersistentSubscriptions.Subscription.swift      # Subscription class (events, ack, nack)
├── PersistentSubscriptions.ReadResponse.swift      # Read response types
├── PersistentSubscriptionsSettingsBuildable.swift  # Settings builder protocol
├── API/                                            # Operations, one file per target
│   ├── PersistentSubscriptions+Specified.swift
│   ├── PersistentSubscriptions+AllStream.swift
│   ├── PersistentSubscriptions+FilterStream.swift
│   └── PersistentSubscriptions+All.swift
├── Target/                                         # PersistentSubscriptionTarget and every target type
└── Usecase/
    ├── PersistentSubscriptions.Ack.swift
    ├── PersistentSubscriptions.Nack.swift
    ├── PersistentSubscriptions.RestartSubsystem.swift
    ├── All/                                        # Server-wide listing
    ├── Specified/                                  # Specific stream operations
    └── AllStream/                                  # $all stream operations
```
