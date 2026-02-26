//
//  AnyProjectionsTarget.swift
//  KurrentDB
//

/// A generic target representing all projections.
///
/// Used to perform operations on all projections, such as listing or restarting the subsystem.
public struct AnyProjectionsTarget: ProjectionsTarget {
    public init() {}
}

extension ProjectionsTarget {
    /// Returns a target representing all projections in any mode.
    public static var anyMode: AnyProjectionsTarget {
        .init()
    }
}
