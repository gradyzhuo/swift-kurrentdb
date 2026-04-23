//
//  ScavengeControllable.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// Capability protocol for operation targets that support stopping a running scavenge.
public protocol ScavengeControllable: OperationsTarget {
    /// Unique identifier of the scavenge operation to control.
    var scavengeId: String { get }
}
