//
//  UnspecifiedContinuousProjectionTarget.swift
//  KurrentDB
//

/// A target for continuous projections where the name is provided at creation time.
///
/// Does not conform to `ProjectionControlable` — use ``SpecifiedContinuousProjectionTarget``
/// or ``NameTarget`` for control operations.
public struct UnspecifiedContinuousProjectionTarget: ProjectionsTarget {
    public init() {}
}

extension ProjectionsTarget {
    /// Returns a target for creating continuous projections without a pre-specified name.
    public static var anyContinuous: UnspecifiedContinuousProjectionTarget {
        .init()
    }
}
