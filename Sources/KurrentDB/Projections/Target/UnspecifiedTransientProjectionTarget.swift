//
//  UnspecifiedTransientProjectionTarget.swift
//  KurrentDB
//

/// Target for transient projections when the name is supplied at creation time rather than up front.
public struct UnspecifiedTransientProjectionTarget: ProjectionsTarget {
    /// Creates an unspecified transient projection target.
    public init() {}
}

extension ProjectionsTarget where Self == UnspecifiedTransientProjectionTarget {
    /// Returns a target for creating transient projections without a pre-specified name.
    public static var anyTransient: UnspecifiedTransientProjectionTarget {
        .init()
    }
}
