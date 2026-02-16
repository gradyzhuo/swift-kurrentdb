//
//  SystemControllable.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A protocol marking operation targets that support system-wide administrative operations.
///
/// Types conforming to `SystemControllable` can perform cluster-wide operations that affect
/// the entire KurrentDB system, such as shutting down the server, merging indexes, or
/// restarting subsystems.
///
/// ## Conforming Types
///
/// - `SystemOperations`: Can perform system-wide administrative tasks
///
/// ## Available Operations
///
/// Targets conforming to this protocol can:
/// - Shutdown the server gracefully
/// - Merge database indexes for optimization
/// - Restart the persistent subscriptions subsystem
///
/// ## Security Considerations
///
/// System operations require administrative privileges and can be disruptive to running services.
/// These operations should be restricted to operators and automated management systems.
///
/// - SeeAlso: `SystemOperations`
public protocol SystemControllable: OperationsTarget {}
