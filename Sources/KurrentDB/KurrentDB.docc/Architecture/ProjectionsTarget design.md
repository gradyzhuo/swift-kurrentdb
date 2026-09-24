# ProjectionsTarget design

The target-based architecture for projection operations, providing compile-time type safety through protocol composition.

## Overview

The Projections API uses a target-based design pattern, consistent with ``StreamsTarget``, ``UsersTarget``, and ``OperationsTarget``. Each target type determines the scope and available operations at compile time.

## Protocol hierarchy

```
ProjectionsTarget (Protocol)
├── ProjectionControlable (Protocol)
│   ├── NameTarget (Struct)
│   ├── SpecifiedContinuousProjectionTarget (Struct)
│   └── SpecifiedTransientProjectionTarget (Struct)
├── OneTimeProjectionTarget (Struct)
├── UnspecifiedContinuousProjectionTarget (Struct)
├── UnspecifiedTransientProjectionTarget (Struct)
└── AnyProjectionsTarget (Struct)
```

## Target types

Each target type represents a different scope and mode of projection operations:

| Target | Purpose | Operations |
|--------|---------|------------|
| ``NameTarget`` | Control a specific named projection (any mode) | `enable()`, `disable()`, `abort()`, `reset()`, `update(query:)`, `delete()`, `detail()`, `result(of:)`, `state(of:)` |
| ``SpecifiedContinuousProjectionTarget`` | Create and control a continuous projection | `create(query:configure:)` + all ``NameTarget`` operations |
| ``SpecifiedTransientProjectionTarget`` | Create and control a transient projection | `create(query:)` + all ``NameTarget`` operations |
| ``OneTimeProjectionTarget`` | Create and list one-time projections | `create(query:)`, `list()` |
| ``UnspecifiedContinuousProjectionTarget`` | Every continuous projection | `list()` |
| ``UnspecifiedTransientProjectionTarget`` | Every transient projection | `list()` |
| ``AnyProjectionsTarget`` | Every projection, and the subsystem | `list()`, `restartSubsystem()` |

## Design decisions

### Why separate creation targets by mode?

KurrentDB projections have three distinct modes with different lifecycle semantics:

1. **SpecifiedContinuousProjectionTarget** — Projections that run indefinitely, processing new events as they arrive. Can be controlled (enabled, disabled, updated, deleted) after creation.
2. **OneTimeProjectionTarget** — Projections that run once and produce a result. Cannot be controlled after creation because they complete immediately.
3. **SpecifiedTransientProjectionTarget** — Projections that run while a client is connected. Can be controlled during the session.

Separating them ensures you cannot call `enable()` on a one-time projection (which has no persistent state to enable), while allowing it on continuous and transient projections.

### Why a separate NameTarget?

``NameTarget`` exists for controlling projections that already exist, regardless of their original creation mode. When you know a projection's name but not its mode, ``NameTarget`` provides the full set of control operations. This mirrors how ``SpecifiedUserTarget`` works in the Users API — you target a specific resource by its identifier.

### Why ProjectionControlable?

The ``ProjectionControlable`` protocol marks targets that support control operations (enable, disable, abort, reset, update, delete, and the state queries). It requires a `name` property, ensuring the target can identify which projection to control. ``OneTimeProjectionTarget``, the unspecified targets and ``AnyProjectionsTarget`` do not conform because they don't name a single projection.

## Static factory methods

Each target has a static factory method on ``ProjectionsTarget``:

```swift
client.projections(name: "my-projection")               // NameTarget (convenience)
client.projections(system: .byCategory)                 // NameTarget for a system projection
client.projections(of: .continuous(name: "stats"))      // SpecifiedContinuousProjectionTarget
client.projections(of: .transient(name: "temp"))        // SpecifiedTransientProjectionTarget
client.projections(of: .onetime)                        // OneTimeProjectionTarget
client.projections(of: .anyContinuous)                  // UnspecifiedContinuousProjectionTarget
client.projections(of: .anyTransient)                   // UnspecifiedTransientProjectionTarget
client.projections(of: .anyMode)                        // AnyProjectionsTarget
```

## Type safety

The target-based design turns invalid combinations into compile errors:

```swift
let query = "fromAll().when({ $any: function(s, e) {} })"

// ✓ Create a continuous projection
try await client.projections(of: .continuous(name: "stats")).create(query: query)

// ✓ Control a named projection
try await client.projections(name: "stats").enable()
try await client.projections(name: "stats").disable()

// ✓ Create a one-time projection
try await client.projections(of: .onetime).create(query: query)

// ✓ List every continuous projection
let continuous = try await client.projections(of: .anyContinuous).list()
```

<!-- snippet:skip -->
```swift
// ✗ Compile error: a one-time projection can't be enabled
try await client.projections(of: .onetime).enable()

// ✗ Compile error: AnyProjectionsTarget can't create
try await client.projections(of: .anyMode).create(query: "fromAll()")
```

## Comparison with other targets

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget |
|---------|--------------|-------------|-------------------|------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` |
| Creation Target | — | `AllUsersTarget` | `SpecifiedContinuousProjectionTarget`, `OneTimeProjectionTarget`, `SpecifiedTransientProjectionTarget` | `ScavengeOperations` |
| Control Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` |
| System Target | `AllStreamsTarget` | — | `AnyProjectionsTarget` | `SystemOperations` |
| Service | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` |

## File structure

```
Sources/KurrentDB/Projections/
├── KurrentDBClient+Projections.swift        # projections(of:), projections(name:), projections(system:)
├── Projections.swift                        # Generic Projections<Target> service + control operations
├── API/
│   ├── Projections+ContinuousMode.swift     # Continuous create / list
│   ├── Projections+TransientMode.swift      # Transient create / list
│   ├── Projections+OneTimeMode.swift        # One-time create / list
│   └── Projections+AnyMode.swift            # List all, restart subsystem
├── Target/                                  # ProjectionsTarget, ProjectionControlable and every target type
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
