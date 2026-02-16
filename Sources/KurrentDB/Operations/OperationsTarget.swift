//
//  OperationsTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A protocol representing a target for server operations in KurrentDB.
///
/// A **target** serves two key purposes in the Operations API:
///
/// ## 1. Specifies the Operation Scope (Where)
///
/// The target identifies what the operation applies to:
/// - `ScavengeOperations`: Scavenge-related operations (start new scavenge)
/// - `ActiveScavenge`: A specific running scavenge operation (stop specific scavenge)
/// - `SystemOperations`: System-wide operations (shutdown, merge indexes, restart subsystems)
/// - `NodeOperations`: Current node operations (resign, set priority)
///
/// ## 2. Constrains Available Operations (What)
///
/// Through protocol composition, different target types enable different capabilities:
/// - Targets conforming to `ScavengeCreatable` can start new scavenge operations
/// - Targets conforming to `ScavengeControllable` can stop specific scavenge operations
/// - Targets conforming to `SystemControllable` can perform system-wide operations
/// - Targets conforming to `NodeControllable` can manage node behavior
/// - The type system prevents invalid operations at compile time
///
/// ## Type Safety
///
/// This design provides compile-time guarantees that operations are only performed on appropriate targets:
///
/// ```swift
/// // Target specifies: scavenge operations (where)
/// // Target constrains: can start new scavenge (what)
/// let scavenges = Operations(target: ScavengeOperations(), ...)
/// let response = try await scavenges.startScavenge(threadCount: 2, startFromChunk: 0)
/// try await scavenges.stopScavenge(scavengeId: "...")  // ✗ Compile error - no such method
///
/// // Target specifies: specific active scavenge (where)
/// // Target constrains: can stop this scavenge (what)
/// let activeScavenge = Operations(target: ActiveScavenge(scavengeId: "abc123"), ...)
/// try await activeScavenge.stopScavenge()              // ✓ Allowed
/// try await activeScavenge.startScavenge(...)          // ✗ Compile error - no such method
///
/// // Target specifies: system operations (where)
/// // Target constrains: can perform system tasks (what)
/// let system = Operations(target: SystemOperations(), ...)
/// try await system.shutdown()                          // ✓ Allowed
/// try await system.mergeIndexes()                      // ✓ Allowed
/// try await system.restartPersistentSubscriptions()    // ✓ Allowed
///
/// // Target specifies: current node (where)
/// // Target constrains: can manage node (what)
/// let node = Operations(target: NodeOperations(), ...)
/// try await node.resignNode()                          // ✓ Allowed
/// try await node.setNodePriority(priority: 10)         // ✓ Allowed
/// ```
///
/// ## Usage
///
/// Create targets using specific constructors:
///
/// ```swift
/// // For starting new scavenges
/// let scavenges = Operations(target: ScavengeOperations(), ...)
/// try await scavenges.startScavenge(threadCount: 2, startFromChunk: 0)
///
/// // For controlling a specific scavenge
/// let active = Operations(target: ActiveScavenge(scavengeId: "abc123"), ...)
/// try await active.stopScavenge()
///
/// // For system operations
/// let system = Operations(target: SystemOperations(), ...)
/// try await system.shutdown()
///
/// // For node operations
/// let node = Operations(target: NodeOperations(), ...)
/// try await node.resignNode()
///
/// // Or use KurrentDBClient convenience methods (recommended)
/// try await client.startScavenge(threadCount: 2, startFromChunk: 0)
/// try await client.stopScavenge(scavengeId: "abc123")
/// ```
///
/// ## Capability Protocols
///
/// - `ScavengeCreatable`: Can start new scavenge operations
/// - `ScavengeControllable`: Can control specific scavenge operations
/// - `SystemControllable`: Can perform system-wide operations
/// - `NodeControllable`: Can manage node behavior
///
/// - Note: This protocol is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// - SeeAlso: `ScavengeCreatable`, `ScavengeControllable`, `SystemControllable`, `NodeControllable`
public protocol OperationsTarget: Sendable {}

/// Extension providing a static factory method to create a `ScavengeOperations` instance.
extension OperationsTarget where Self == ScavengeOperations {
    public static var scavenge: ScavengeOperations {
        .init()
    }
}

/// Extension providing a static factory method to create an `ActiveScavenge` instance.
extension OperationsTarget where Self == ActiveScavenge {
    public static func activeScavenge(scavengeId: String) -> ActiveScavenge {
        .init(scavengeId: scavengeId)
    }
}

/// Extension providing a static factory method to create a `SystemOperations` instance.
extension OperationsTarget where Self == SystemOperations {
    public static var system: SystemOperations {
        .init()
    }
}

/// Extension providing a static factory method to create a `NodeOperations` instance.
extension OperationsTarget where Self == NodeOperations {
    public static var node: NodeOperations {
        .init()
    }
}
