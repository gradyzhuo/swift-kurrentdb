# OperationsTarget design

The target-based architecture for server operations, providing compile-time type safety through protocol composition.

## Overview

The Operations API uses a target-based design pattern, consistent with ``StreamsTarget``, ``UsersTarget``, and ``ProjectionsTarget``. Each target type determines the scope and available operations at compile time.

## Protocol hierarchy

```
OperationsTarget (Protocol)
├── ScavengeCreatable (Protocol)
│   └── ScavengeOperations (Struct)
├── ScavengeControllable (Protocol)
│   └── ActiveScavenge (Struct)
├── SystemControllable (Protocol)
│   └── SystemOperations (Struct)
└── NodeControllable (Protocol)
    └── NodeOperations (Struct)
```

## Capability protocols

Each capability protocol defines a specific scope of operations:

| Protocol | Target | Purpose | Operations |
|----------|--------|---------|------------|
| ``ScavengeCreatable`` | ``ScavengeOperations`` | Start new scavenge operations | `startScavenge(threadCount:startFromChunk:)` |
| ``ScavengeControllable`` | ``ActiveScavenge`` | Control a specific running scavenge (requires `scavengeId`) | `stopScavenge()` |
| ``SystemControllable`` | ``SystemOperations`` | System-wide administrative tasks | `shutdown()`, `mergeIndexes()`, `restartPersistentSubscriptions()` |
| ``NodeControllable`` | ``NodeOperations`` | Cluster node behavior management | `resignNode()`, `setNodePriority(priority:)` |

## Design decisions

### Why four capability protocols?

Server operations naturally fall into four distinct categories with different scopes:

1. **ScavengeCreatable** — Starting a scavenge is a system-wide creation operation (no scavenge ID exists yet)
2. **ScavengeControllable** — Stopping a scavenge requires targeting a specific running scavenge (by ID)
3. **SystemControllable** — System-wide administrative tasks that affect the entire cluster
4. **NodeControllable** — Operations scoped to the current node only

This separation mirrors the create/control pattern in ``UsersTarget`` (`AllUsersTarget` vs `SpecifiedUserTarget`), where creation is a broad-scope operation and control targets a specific resource.

### Why separate ScavengeOperations and ActiveScavenge?

Scavenge operations have two distinct lifecycle phases:

1. **Creation** — Starting a new scavenge (no scavenge ID yet, returns one)
2. **Control** — Managing an existing scavenge (requires scavenge ID)

Separating them ensures you cannot accidentally call `stopScavenge()` without a scavenge ID, and cannot call `startScavenge()` on an active scavenge target.

## Static factory methods

Each target has a static factory method on ``OperationsTarget`` via `where Self ==` extensions:

```swift
client.operations(of: .scavenge)                          // ScavengeOperations
client.operations(of: .activeScavenge(scavengeId: "...")) // ActiveScavenge
client.operations(of: .system)                            // SystemOperations
client.operations(of: .node)                              // NodeOperations
```

## Type safety

The target-based design provides compile-time guarantees that prevent invalid operation combinations:

```swift
// ✓ Correct: Start scavenge on ScavengeOperations
try await client.operations(of: .scavenge)
    .startScavenge(threadCount: 2, startFromChunk: 0)

// ✗ Compile error: Cannot stop without specifying a scavenge ID
try await client.operations(of: .scavenge).stopScavenge()

// ✓ Correct: Stop a specific scavenge
try await client.operations(of: .activeScavenge(scavengeId: "abc"))
    .stopScavenge()

// ✗ Compile error: Cannot start from ActiveScavenge target
try await client.operations(of: .activeScavenge(scavengeId: "abc"))
    .startScavenge(threadCount: 2, startFromChunk: 0)

// ✗ Compile error: Cannot mix system and scavenge operations
try await client.operations(of: .system).startScavenge(...)
try await client.operations(of: .node).shutdown()
```

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget |
|---------|--------------|-------------|-------------------|------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` |
| Creation Target | — | `AllUsersTarget` | `ContinuousTarget`, `OneTimeTarget`, `TransientTarget` | `ScavengeOperations` |
| Control Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` |
| System Target | `AllStreams` | — | `AnyProjectionsTarget` | `SystemOperations` |
| Node Target | — | — | — | `NodeOperations` |
| Service Actor | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` |

## File structure

```
Sources/KurrentDB/Operations/
├── OperationsTarget.swift                 # Base protocol + static factory methods
├── Protocols/
│   ├── ScavengeCreatable.swift            # Scavenge creation capability
│   ├── ScavengeControllable.swift         # Scavenge control capability
│   ├── SystemControllable.swift           # System operations capability
│   └── NodeControllable.swift             # Node management capability
├── Targets/
│   ├── ScavengeOperations.swift           # Start scavenge target
│   ├── ActiveScavenge.swift               # Stop scavenge target (holds scavengeId)
│   ├── SystemOperations.swift             # System-wide operations target
│   └── NodeOperations.swift               # Node management target
├── Operations.swift                       # Generic Operations<Target> actor
└── Usecase/                               # gRPC usecase implementations
```
