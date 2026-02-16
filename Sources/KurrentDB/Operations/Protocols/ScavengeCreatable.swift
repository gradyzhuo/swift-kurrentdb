//
//  ScavengeCreatable.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A protocol marking operation targets that support starting new scavenge operations.
///
/// Types conforming to `ScavengeCreatable` can initiate scavenge operations to reclaim
/// disk space by removing deleted events from database chunks.
///
/// ## Conforming Types
///
/// - `ScavengeOperations`: Can start new scavenge operations
///
/// ## Available Operations
///
/// Targets conforming to this protocol can:
/// - Start new scavenge operations with configurable thread count and starting position
///
/// - SeeAlso: `ScavengeControllable`, `ScavengeOperations`
public protocol ScavengeCreatable: OperationsTarget {}
