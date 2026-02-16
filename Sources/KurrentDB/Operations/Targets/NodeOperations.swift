//
//  NodeOperations.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A target representing operations on the current cluster node.
///
/// `NodeOperations` is used for managing the behavior and role of the current node within
/// a KurrentDB cluster, such as resigning from leadership or adjusting election priority.
///
/// ## Capabilities
///
/// This target conforms to `NodeControllable`, enabling:
/// - Resigning the node from its current role in the cluster
/// - Setting the node's priority for leader election
///
/// ## Usage
///
/// ```swift
/// let node = Operations(target: NodeOperations(), ...)
///
/// // Resign from current role
/// try await node.resignNode()
///
/// // Set node priority for elections
/// try await node.setNodePriority(priority: 10)
/// ```
///
/// ## Use Cases
///
/// - Gracefully stepping down a leader node during maintenance
/// - Adjusting node priorities to influence leader election
/// - Managing cluster rebalancing and node rotation
/// - Preparing nodes for updates or decommissioning
///
/// - SeeAlso: `NodeControllable`, `OperationsTarget`
public struct NodeOperations: NodeControllable {
    /// Initializes a target for node management operations.
    public init() {}
}
