//
//  ScavengeControllable.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A protocol marking operation targets that support controlling specific scavenge operations.
///
/// Types conforming to `ScavengeControllable` can stop running scavenge operations
/// identified by their scavenge ID.
///
/// ## Required Property
///
/// Conforming types must provide a `scavengeId` property that uniquely identifies the target scavenge.
///
/// ## Conforming Types
///
/// - `ActiveScavenge`: Can control a specific running scavenge operation
///
/// ## Available Operations
///
/// Targets conforming to this protocol can:
/// - Stop the identified scavenge operation gracefully
///
/// - SeeAlso: `ScavengeCreatable`, `ActiveScavenge`
public protocol ScavengeControllable: OperationsTarget {
    /// The unique identifier of the scavenge operation to control.
    var scavengeId: String { get }
}
