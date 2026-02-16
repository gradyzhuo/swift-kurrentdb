//
//  ScavengeOperations.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A target representing scavenge operations in the KurrentDB system.
///
/// `ScavengeOperations` is used for starting new scavenge operations to reclaim disk space
/// by removing deleted events from database chunks. This target type supports scavenge
/// creation operations.
///
/// ## Capabilities
///
/// This target conforms to `ScavengeCreatable`, enabling:
/// - Starting new scavenge operations with configurable parallelism
/// - Specifying starting positions for resuming interrupted scavenges
///
/// ## Usage
///
/// ```swift
/// let scavenges = Operations(target: ScavengeOperations(), ...)
///
/// // Start a new scavenge
/// let response = try await scavenges.startScavenge(
///     threadCount: 2,
///     startFromChunk: 0
/// )
/// print("Started scavenge: \(response.scavengeId)")
/// ```
///
/// - SeeAlso: `ScavengeCreatable`, `OperationsTarget`, `ActiveScavenge`
public struct ScavengeOperations: ScavengeCreatable {
    /// Initializes a target representing scavenge operations.
    public init() {}
}
