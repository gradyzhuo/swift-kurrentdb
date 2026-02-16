//
//  NodeControllable.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A protocol marking operation targets that support node management operations.
///
/// Types conforming to `NodeControllable` can manage cluster node behavior, such as
/// resigning from leadership or adjusting node priority for election purposes.
///
/// ## Conforming Types
///
/// - `NodeOperations`: Can manage the current cluster node
///
/// ## Available Operations
///
/// Targets conforming to this protocol can:
/// - Resign the node from its current role in the cluster
/// - Set the node's priority for leader election
///
/// ## Use Cases
///
/// - Gracefully stepping down a leader node during maintenance
/// - Adjusting node priorities to influence leader election
/// - Managing cluster rebalancing and node rotation
///
/// - SeeAlso: `NodeOperations`
public protocol NodeControllable: OperationsTarget {}
