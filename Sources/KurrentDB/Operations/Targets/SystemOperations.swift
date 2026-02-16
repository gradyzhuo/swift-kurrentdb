//
//  SystemOperations.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A target representing system-wide administrative operations.
///
/// `SystemOperations` is used for cluster-wide operations that affect the entire KurrentDB
/// system, such as shutting down the server, merging indexes, or restarting subsystems.
///
/// ## Capabilities
///
/// This target conforms to `SystemControllable`, enabling:
/// - Graceful server shutdown
/// - Database index merging for optimization
/// - Restarting the persistent subscriptions subsystem
///
/// ## Usage
///
/// ```swift
/// let system = Operations(target: SystemOperations(), ...)
///
/// // Shutdown the server
/// try await system.shutdown()
///
/// // Merge indexes
/// try await system.mergeIndexes()
///
/// // Restart persistent subscriptions
/// try await system.restartPersistentSubscriptions()
/// ```
///
/// - Warning: System operations require administrative privileges and can be disruptive.
///   Exercise caution when using in production environments.
///
/// - SeeAlso: `SystemControllable`, `OperationsTarget`
public struct SystemOperations: SystemControllable {
    /// Initializes a target for system-wide operations.
    public init() {}
}
