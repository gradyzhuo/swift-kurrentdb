//
//  ActiveScavenge.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// A target representing a specific active scavenge operation.
///
/// `ActiveScavenge` is used for operations on a running scavenge, identified by its unique
/// scavenge ID. This target type supports stopping the identified scavenge operation.
///
/// ## Capabilities
///
/// This target conforms to `ScavengeControllable`, enabling:
/// - Stopping the specific scavenge operation gracefully
///
/// ## Usage
///
/// ```swift
/// let activeScavenge = Operations(target: ActiveScavenge(scavengeId: "abc123"), ...)
///
/// // Stop the specific scavenge
/// let response = try await activeScavenge.stopScavenge()
/// print("Stopped scavenge: \(response.scavengeId)")
/// ```
///
/// - SeeAlso: `ScavengeControllable`, `OperationsTarget`, `ScavengeOperations`
public struct ActiveScavenge: ScavengeControllable {
    /// The unique identifier of the scavenge operation.
    public let scavengeId: String

    /// Initializes a target for a specific active scavenge.
    ///
    /// - Parameter scavengeId: The unique identifier of the scavenge operation.
    public init(scavengeId: String) {
        self.scavengeId = scavengeId
    }
}
