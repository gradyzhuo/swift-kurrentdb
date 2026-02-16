# ProjectionsTarget design

The target-based architecture for projection operations, providing compile-time type safety through protocol composition.

## Overview

The Projections API uses a target-based design pattern, consistent with ``StreamsTarget``, ``UsersTarget``, and ``OperationsTarget``. Each target type determines the scope and available operations at compile time.

## Protocol hierarchy

```
ProjectionsTarget (Protocol)
├── ProjectionControlable (Protocol)
│   ├── NameTarget (Struct)
│   ├── ContinuousTarget (Struct)
│   └── TransientTarget (Struct)
├── OneTimeTarget (Struct)
└── AnyProjectionsTarget (Struct)
```

## Target types

Each target type represents a different scope and mode of projection operations:

| Target | Purpose | Operations |
|--------|---------|------------|
| ``NameTarget`` | Control a specific named projection (any mode) | `enable()`, `disable()`, `update(query:)`, `delete()`, `reset()`, `result()`, `state()`, `statistics()` |
| ``ContinuousTarget`` | Create and control a continuous projection | `create(query:)` + all ``NameTarget`` operations |
| ``OneTimeTarget`` | Create a one-time projection | `create(query:)` |
| ``TransientTarget`` | Create and control a transient projection | `create(query:)` + all ``NameTarget`` operations |
| ``AnyProjectionsTarget`` | System-wide projection operations | `list(for:)`, `restartSubsystem()` |

## Design decisions

### Why separate creation targets by mode?

KurrentDB projections have three distinct modes with different lifecycle semantics:

1. **ContinuousTarget** — Projections that run indefinitely, processing new events as they arrive. Can be controlled (enabled, disabled, updated, deleted) after creation.
2. **OneTimeTarget** — Projections that run once and produce a result. Cannot be controlled after creation because they complete immediately.
3. **TransientTarget** — Projections that run while a client is connected. Can be controlled during the session.

Separating them ensures you cannot call `enable()` on a one-time projection (which has no persistent state to enable), while allowing it on continuous and transient projections.

### Why a separate NameTarget?

``NameTarget`` exists for controlling projections that already exist, regardless of their original creation mode. When you know a projection's name but not its mode, ``NameTarget`` provides the full set of control operations. This mirrors how ``SpecifiedUserTarget`` works in the Users API — you target a specific resource by its identifier.

### Why ProjectionControlable?

The ``ProjectionControlable`` protocol marks targets that support control operations (enable, disable, update, delete, reset). It requires a `name` property, ensuring the target can identify which projection to control. ``OneTimeTarget`` and ``AnyProjectionsTarget`` do not conform because they don't support individual projection control.

## Static factory methods

Each target has a static factory method on ``ProjectionsTarget``:

```swift
client.projections(name: "my-projection")       // NameTarget (via convenience)
client.projections(of: .continuous(name: "stats"))   // ContinuousTarget
client.projections(of: .onetime)                     // OneTimeTarget
client.projections(of: .transient(name: "temp"))     // TransientTarget
client.projections(of: .any)                         // AnyProjectionsTarget
```

## Type safety

The target-based design provides compile-time guarantees that prevent invalid operation combinations:

```swift
// ✓ Correct: Create a continuous projection
try await client.createContinuousProjection(name: "stats", query: query)

// ✓ Correct: Control a named projection
try await client.enableProjection(name: "stats")
try await client.disableProjection(name: "stats")

// ✓ Correct: Create a one-time projection
try await client.createOneTimeProjection(query: query)

// ✗ Compile error: Cannot enable a one-time projection
let oneTime = Projections(target: .onetime, ...)
try await oneTime.enable()

// ✗ Compile error: Cannot create from AnyProjectionsTarget
let any = Projections(target: .any, ...)
try await any.create(query: query)

// ✓ Correct: List all projections
try await client.listAllProjections(mode: .continuous)
```

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget |
|---------|--------------|-------------|-------------------|------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` |
| Creation Target | — | `AllUsersTarget` | `ContinuousTarget`, `OneTimeTarget`, `TransientTarget` | `ScavengeOperations` |
| Control Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` |
| System Target | `AllStreams` | — | `AnyProjectionsTarget` | `SystemOperations` |
| Service Actor | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` |

## File structure

```
Sources/KurrentDB/Projections/
├── Protocols/
│   ├── ProjectionsTarget.swift              # Base protocol + static factory methods
│   ├── ProjectionControlable.swift          # Control capability protocol
│   ├── NameTarget.swift                     # Named projection target
│   ├── AnyTarget.swift                      # All projections target
│   ├── ProjectionTarget+Continuous.swift    # Continuous projection target
│   ├── ProjectionTarget+OneTime.swift       # One-time projection target
│   └── ProjectionTarget+Transient.swift     # Transient projection target
├── Projections.swift                        # Generic Projections<Target> actor
├── Projections+ContinuousMode.swift         # Continuous mode extensions
├── Projections+OneTimeMode.swift            # One-time mode extensions
├── Projections+TransientMode.swift          # Transient mode extensions
└── Usecase/
    ├── Create/
    │   ├── Projections.ContinuousCreate.swift
    │   ├── Projections.OneTimeCreate.swift
    │   └── Projections.TransientCreate.swift
    ├── Projections.Enable.swift
    ├── Projections.Disable.swift
    ├── Projections.Update.swift
    ├── Projections.Delete.swift
    ├── Projections.Reset.swift
    ├── Projections.Result.swift
    ├── Projections.State.swift
    ├── Projections.Statistics.swift
    └── Projections.RestartSubsystem.swift
```
