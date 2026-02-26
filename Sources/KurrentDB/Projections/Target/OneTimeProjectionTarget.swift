//
//  OneTimeProjectionTarget.swift
//  KurrentDB
//

/// A target for one-time (ephemeral) projections that run to completion and then stop.
public struct OneTimeProjectionTarget: ProjectionsTarget {
    public init() {}
}

extension ProjectionsTarget where Self == OneTimeProjectionTarget {
    /// Returns a target for one-time projections.
    public static var onetime: OneTimeProjectionTarget {
        .init()
    }
}
