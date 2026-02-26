//
//  StreamsTarget.swift
//  KurrentDB
//

/// A protocol representing a target for stream operations in KurrentDB.
///
/// A **target** serves two key purposes in the Streams API:
///
/// ## 1. Specifies the Operation Scope (Where)
///
/// The target identifies which streams the operation applies to:
/// - `SpecifiedStream`: Operates on a specific named stream
/// - `AllStreams`: Operates on the global `$all` stream containing all events
/// - `MultiStreams`: Operates on multiple streams simultaneously
/// - `ProjectionStream`: Operates on system projection streams
///
/// ## 2. Constrains Available Operations (What)
///
/// Through protocol composition, different target types enable different capabilities:
/// - Targets conforming to `SpecifiedStreamTarget` support append, read, delete, and subscription operations
/// - `AllStreams` only supports read and subscription operations (cannot append to `$all`)
/// - `MultiStreams` only supports batch append operations
/// - The type system prevents invalid operations at compile time
///
/// ## Usage
///
/// Create targets using static factory methods:
///
/// ```swift
/// let orders = StreamsTarget.specified("orders")
/// let all = StreamsTarget.all
/// let multi = StreamsTarget.multiple
/// let byType = StreamsTarget.byEventType("OrderCreated")
/// ```
///
/// - Note: This protocol is marked as `Sendable`.
/// - SeeAlso: `SpecifiedStreamTarget`, `AllStreams`, `MultiStreams`, `ProjectionStream`
public protocol StreamsTarget: Sendable {}
