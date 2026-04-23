//
//  AnyProjectionsTarget.swift
//  KurrentDB
//

/// Target representing all projections across every mode.
public struct AnyProjectionsTarget: ProjectionsTarget {
    /// Creates an any-mode projections target.
    public init() {}
}

extension ProjectionsTarget where Self == AnyProjectionsTarget {
    /// Returns a target representing all projections in any mode.
    public static var anyMode: AnyProjectionsTarget {
        .init()
    }
}
