//
//  ProjectionsTarget.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/12.
//

/// A protocol representing a target for projection operations in KurrentDB.
///
/// A **target** serves two key purposes in the Projections API:
///
/// ## 1. Specifies the Operation Scope (Where)
///
/// The target identifies which projection(s) the operation applies to:
/// - `NameTarget`: Operates on a specific named projection
/// - `ContinuousTarget`: Operates on a continuous projection with specific name
/// - `OneTimeTarget`: Operates on one-time projections (scope is execution-based)
/// - `TransientTarget`: Operates on a transient projection with specific name
/// - `AnyProjectionsTarget`: Operates across all projections
///
/// ## 2. Constrains Available Operations (What)
///
/// Through protocol composition, different target types enable different capabilities:
/// - Targets conforming to `ProjectionControllable` support enable, disable, update, delete, reset operations
/// - `OneTimeTarget` only supports creation (one-time projections don't persist for control operations)
/// - `AnyProjectionsTarget` supports listing and subsystem restart operations
/// - The type system prevents invalid operations at compile time
///
/// ## Type Safety
///
/// This design provides compile-time guarantees that operations are only performed on appropriate projection types:
///
/// ```swift
/// // Target specifies: specific projection "order-analytics" (where)
/// // Target constrains: can control this projection (what)
/// let projection = Projections(target: .named("order-analytics"), ...)
/// try await projection.enable()                   // ✓ Allowed
/// try await projection.disable()                  // ✓ Allowed
/// try await projection.update(query: newQuery)    // ✓ Allowed
///
/// // Target specifies: continuous projection "stats" (where)
/// // Target constrains: can create and control (what)
/// let continuous = Projections(target: .continuous(name: "stats"), ...)
/// try await continuous.create(query: query)       // ✓ Allowed
/// try await continuous.enable()                   // ✓ Allowed
///
/// // Target specifies: one-time execution (where)
/// // Target constrains: can only create (what)
/// let oneTime = Projections(target: .onetime, ...)
/// try await oneTime.create(query: query)          // ✓ Allowed
/// try await oneTime.enable()                      // ✗ Compile error - no such method
///
/// // Target specifies: all projections (where)
/// // Target constrains: can list and restart subsystem (what)
/// let all = Projections(target: .any, ...)
/// try await all.list(for: .continuous)            // ✓ Allowed
/// try await all.enable()                          // ✗ Compile error - no such method
/// ```
///
/// ## Usage
///
/// Create targets using static factory methods:
///
/// ```swift
/// // Named projection (any mode)
/// let named = ProjectionsTarget.named("my-projection")
///
/// // Continuous projection
/// let continuous = ProjectionsTarget.continuous(name: "order-stats")
///
/// // One-time projection
/// let oneTime = ProjectionsTarget.onetime
///
/// // Transient projection
/// let transient = ProjectionsTarget.transient(name: "temp-analysis")
///
/// // All projections
/// let all = ProjectionsTarget.any
///
/// // Or use KurrentDBClient convenience methods (recommended)
/// try await client.createContinuousProjection(name: "stats", query: query)
/// try await client.enableProjection(name: "stats")
/// try await client.listAllProjections(mode: .continuous)
/// ```
///
/// ## Capability Protocols
///
/// - `ProjectionControllable`: Marks targets that support control operations (enable, disable, update, etc.)
///
/// - Note: This protocol is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// - SeeAlso: `ProjectionControllable`, `NameTarget`, `ContinuousTarget`, `OneTimeTarget`, `TransientTarget`, `AnyProjectionsTarget`
public protocol ProjectionsTarget: Sendable {}

/// Extension providing static methods to create `ProjectionStream` instances.
extension ProjectionsTarget {
    public static func named(_ name: String) -> NameTarget {
        .init(name: name)
    }

    public static func continuous(name: String) -> ContinuousTarget {
        .init(name: name)
    }

    public static var onetime: OneTimeTarget {
        .init()
    }

    public static func transient(name: String) -> TransientTarget {
        .init(name: name)
    }

    public static var any: AnyProjectionsTarget {
        .init()
    }
}
