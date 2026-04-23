//
//  OneTimeProjectionTarget.swift
//  KurrentDB
//

/// Target for one-time projections that process existing events once and then stop.
public struct OneTimeProjectionTarget: ProjectionsTarget {
    /// Creates a one-time projection target.
    public init() {}
}

extension ProjectionsTarget where Self == OneTimeProjectionTarget {
    /// Returns a target for one-time projections.
    public static var onetime: OneTimeProjectionTarget {
        .init()
    }
}
