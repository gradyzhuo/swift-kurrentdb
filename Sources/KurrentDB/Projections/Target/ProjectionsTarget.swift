//
//  ProjectionsTarget.swift
//  KurrentDB
//

/// A protocol representing a target for projection operations in KurrentDB.
///
/// A **target** serves two key purposes in the Projections API:
///
/// ## 1. Specifies the Operation Scope (Where)
///
/// The target identifies which projection(s) the operation applies to:
/// - `NameTarget`: Operates on a specific named projection
/// - `SpecifiedContinuousProjectionTarget`: Operates on a continuous projection with specific name
/// - `OneTimeProjectionTarget`: Operates on one-time projections (scope is execution-based)
/// - `SpecifiedTransientProjectionTarget`: Operates on a transient projection with specific name
/// - `AnyProjectionsTarget`: Operates across all projections
///
/// ## 2. Constrains Available Operations (What)
///
/// Through protocol composition, different target types enable different capabilities:
/// - Targets conforming to `ProjectionControlable` support enable, disable, update, delete, reset operations
/// - `OneTimeProjectionTarget` only supports creation
/// - `AnyProjectionsTarget` supports listing and subsystem restart operations
///
/// ## Usage
///
/// Create targets using static factory methods:
///
/// ```swift
/// let named      = ProjectionsTarget.anyMode(name: "my-projection")
/// let continuous = ProjectionsTarget.continuous(name: "order-stats")
/// let oneTime    = ProjectionsTarget.onetime
/// let transient  = ProjectionsTarget.transient(name: "temp-analysis")
/// let all        = ProjectionsTarget.anyMode
/// ```
///
/// - Note: This protocol is marked as `Sendable`.
/// - SeeAlso: `ProjectionControlable`, `NameTarget`, `AnyProjectionsTarget`
public protocol ProjectionsTarget: Sendable {}
