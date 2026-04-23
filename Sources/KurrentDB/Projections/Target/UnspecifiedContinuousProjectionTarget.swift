//
//  UnspecifiedContinuousProjectionTarget.swift
//  KurrentDB
//

/// Target for continuous projections when the name is supplied at creation time rather than up front.
public struct UnspecifiedContinuousProjectionTarget: ProjectionsTarget {
    /// Creates an unspecified continuous projection target.
    public init() {}
}

extension ProjectionsTarget where Self == UnspecifiedContinuousProjectionTarget {
    /// Returns a target for creating continuous projections without a pre-specified name.
    public static var anyContinuous: UnspecifiedContinuousProjectionTarget {
        .init()
    }
}
