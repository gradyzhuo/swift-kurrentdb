# OperationsTarget Design

This document explains the target-based design for server operations, following the same pattern as `StreamsTarget`, `UsersTarget`, and `ProjectionsTarget`.

## Architecture

### Protocol Hierarchy

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

### Capability Protocols

#### 1. ScavengeCreatable

Marks targets that can start new scavenge operations.

**Operations Available:**
- `startScavenge(threadCount:startFromChunk:)` - Start new scavenge operations to reclaim disk space

**Conforming Types:**
- `ScavengeOperations` - Represents scavenge operation scope

#### 2. ScavengeControllable

Marks targets that can control specific running scavenge operations.

**Required Property:**
- `scavengeId: String` - The unique identifier of the scavenge to control

**Operations Available:**
- `stopScavenge()` - Stop the specific scavenge operation gracefully

**Conforming Types:**
- `ActiveScavenge` - Represents a specific running scavenge

#### 3. SystemControllable

Marks targets that can perform system-wide administrative operations.

**Operations Available:**
- `shutdown()` - Gracefully shutdown the server
- `mergeIndexes()` - Merge database indexes for optimization
- `restartPersistentSubscriptions()` - Restart the persistent subscriptions subsystem

**Conforming Types:**
- `SystemOperations` - Represents system-wide operations

#### 4. NodeControllable

Marks targets that can manage cluster node behavior.

**Operations Available:**
- `resignNode()` - Resign the node from its current role
- `setNodePriority(priority:)` - Set node's priority for leader election

**Conforming Types:**
- `NodeOperations` - Represents current node operations

## Usage Examples

### Starting Scavenge Operations

```swift
// Using Operations<ScavengeOperations> directly
let scavenges = Operations(target: ScavengeOperations(), selector: selector, ...)
let response = try await scavenges.startScavenge(
    threadCount: 2,
    startFromChunk: 0
)
print("Started scavenge: \(response.scavengeId)")

// Using KurrentDBClient convenience method (recommended)
let response = try await client.startScavenge(
    threadCount: 2,
    startFromChunk: 0
)
```

### Controlling Active Scavenge

```swift
// Using Operations<ActiveScavenge> directly
let activeScavenge = Operations(target: ActiveScavenge(scavengeId: "abc123"), ...)
let response = try await activeScavenge.stopScavenge()

// Using KurrentDBClient convenience method (recommended)
let response = try await client.stopScavenge(scavengeId: "abc123")
```

### System Operations

```swift
// Using Operations<SystemOperations> directly
let system = Operations(target: SystemOperations(), ...)

// Shutdown
try await system.shutdown()

// Merge indexes
try await system.mergeIndexes()

// Restart persistent subscriptions subsystem
try await system.restartPersistentSubscriptions()
```

### Node Management

```swift
// Using Operations<NodeOperations> directly
let node = Operations(target: NodeOperations(), ...)

// Resign from current role
try await node.resignNode()

// Set election priority
try await node.setNodePriority(priority: 10)
```

## Type Safety Benefits

The target-based design provides compile-time type safety:

1. **Scavenge creation** is only available on `ScavengeOperations` (via `ScavengeCreatable`)
2. **Scavenge control** is only available on `ActiveScavenge` (via `ScavengeControllable`)
3. **System operations** are only available on `SystemOperations` (via `SystemControllable`)
4. **Node operations** are only available on `NodeOperations` (via `NodeControllable`)
5. Cannot accidentally call wrong operations on wrong targets

## File Structure

```
Sources/KurrentDB/Operations/
├── OperationsTarget.swift                 # Base protocol
├── Protocols/
│   ├── ScavengeCreatable.swift            # Scavenge creation capability
│   ├── ScavengeControllable.swift         # Scavenge control capability
│   ├── SystemControllable.swift           # System operations capability
│   └── NodeControllable.swift             # Node management capability
├── Targets/
│   ├── ScavengeOperations.swift           # Scavenge operations target
│   ├── ActiveScavenge.swift               # Active scavenge target
│   ├── SystemOperations.swift             # System operations target
│   └── NodeOperations.swift               # Node operations target
├── Operations.swift                       # Generic Operations<Target: OperationsTarget> actor
└── KurrentDBClient+ServerOperations.swift # Client extension with convenience methods
```

## Comparison with Other Targets

This design follows the same pattern as other Target systems:

| Concept | StreamsTarget | UsersTarget | ProjectionsTarget | OperationsTarget |
|---------|--------------|-------------|-------------------|------------------|
| Base Protocol | `StreamsTarget` | `UsersTarget` | `ProjectionsTarget` | `OperationsTarget` |
| Creation Target | - | `AllUsersTarget` | `ContinuousTarget`, `OneTimeTarget`, `TransientTarget` | `ScavengeOperations` |
| Control Target | `SpecifiedStream` | `SpecifiedUserTarget` | `NameTarget` | `ActiveScavenge` |
| System Target | `AllStreams` | - | `AnyProjectionsTarget` | `SystemOperations` |
| Node Target | - | - | - | `NodeOperations` |
| Service Actor | `Streams<Target>` | `Users<Target>` | `Projections<Target>` | `Operations<Target>` |

## Operation Categories

### Scavenge Operations
**Purpose**: Disk space reclamation and performance optimization
- Start new scavenge operations
- Stop running scavenge operations

### System Operations
**Purpose**: Cluster-wide administrative tasks
- Server shutdown
- Index optimization
- Subsystem management

### Node Operations
**Purpose**: Cluster node behavior management
- Leadership management
- Election priority configuration

## Benefits

1. **Type Safety**: Operations are restricted to appropriate target types at compile time
2. **Clear Intent**: Target type explicitly indicates the scope of operations
3. **Consistency**: Follows the same pattern as StreamsTarget, UsersTarget, and ProjectionsTarget
4. **Extensibility**: Easy to add new target types or capabilities
5. **Documentation**: Self-documenting code through type system
6. **API Clarity**: Separate interfaces for different operational scopes

## Design Decisions

### Why Four Capability Protocols?

Unlike other Target systems that have 1-2 capability protocols, `OperationsTarget` uses four because server operations naturally fall into four distinct categories:

1. **ScavengeCreatable** - Starting scavenges (system scope, creation)
2. **ScavengeControllable** - Stopping scavenges (specific scavenge scope, control)
3. **SystemControllable** - System-wide admin tasks (cluster scope)
4. **NodeControllable** - Node management (single node scope)

This separation ensures:
- Cannot start scavenge on ActiveScavenge target
- Cannot stop scavenge without scavenge ID
- Cannot call system operations on scavenge targets
- Clear separation of concerns

### Why Separate ScavengeOperations and ActiveScavenge?

Scavenge operations have two distinct phases:
1. **Creation**: Starting a new scavenge (no scavenge ID yet)
2. **Control**: Managing an existing scavenge (requires scavenge ID)

This mirrors the create/manage pattern seen in UsersTarget (AllUsersTarget vs SpecifiedUserTarget).

### Type Safety Example

```swift
// ✓ Correct: Start scavenge on ScavengeOperations
let scavenges = Operations(target: ScavengeOperations(), ...)
try await scavenges.startScavenge(threadCount: 2, startFromChunk: 0)

// ✗ Compile error: Cannot stop without scavenge ID
try await scavenges.stopScavenge()  // Method doesn't exist

// ✓ Correct: Stop specific scavenge
let active = Operations(target: ActiveScavenge(scavengeId: "abc"), ...)
try await active.stopScavenge()

// ✗ Compile error: Cannot start from ActiveScavenge
try await active.startScavenge(...)  // Method doesn't exist

// ✓ Correct: System operations
let system = Operations(target: SystemOperations(), ...)
try await system.shutdown()

// ✗ Compile error: Cannot do scavenge operations
try await system.startScavenge(...)  // Method doesn't exist
```

## Security Considerations

All operations require administrative privileges:
- Users must be in `$admins` or `$ops` groups
- Operations can be disruptive to running services
- Should be restricted to operators and automated management systems
- Use with caution in production environments

## Example: Complete Scavenge Workflow

```swift
// 1. Start a scavenge
let startResponse = try await client.startScavenge(
    threadCount: 2,
    startFromChunk: 0
)
let scavengeId = startResponse.scavengeId
print("Started scavenge: \(scavengeId)")

// 2. Monitor progress (application-specific)
// Check logs, metrics, or server status

// 3. If needed, stop the scavenge
if needsToStop {
    let stopResponse = try await client.stopScavenge(scavengeId: scavengeId)
    print("Stopped scavenge: \(stopResponse.result)")
}

// 4. Optionally resume later
let resumeResponse = try await client.startScavenge(
    threadCount: 2,
    startFromChunk: lastCompletedChunk
)
```
