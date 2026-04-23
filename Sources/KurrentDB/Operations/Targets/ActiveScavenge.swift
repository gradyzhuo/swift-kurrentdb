//
//  ActiveScavenge.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2026/2/15.
//

/// Target scoped to a specific running scavenge operation, enabling it to be stopped.
public struct ActiveScavenge: ScavengeControllable {
    /// Unique identifier of the active scavenge operation.
    public let scavengeId: String

    /// Creates a target for the scavenge with the given ID.
    ///
    /// - Parameter scavengeId: Unique identifier of the scavenge operation.
    public init(scavengeId: String) {
        self.scavengeId = scavengeId
    }
}
