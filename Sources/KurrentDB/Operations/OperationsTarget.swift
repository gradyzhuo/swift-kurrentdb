//
//  OperationsTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// Marker protocol for types that identify the scope of a server operation.
public protocol OperationsTarget: Sendable {}

extension OperationsTarget where Self == ScavengeOperations {
    /// Target for starting new scavenge operations.
    public static var scavenge: ScavengeOperations {
        .init()
    }
}

extension OperationsTarget where Self == ActiveScavenge {
    /// Target for controlling the running scavenge with the given ID.
    public static func activeScavenge(scavengeId: String) -> ActiveScavenge {
        .init(scavengeId: scavengeId)
    }
}

extension OperationsTarget where Self == SystemOperations {
    /// Target for system-wide administrative operations.
    public static var system: SystemOperations {
        .init()
    }
}

extension OperationsTarget where Self == NodeOperations {
    /// Target for cluster node management operations.
    public static var node: NodeOperations {
        .init()
    }
}
