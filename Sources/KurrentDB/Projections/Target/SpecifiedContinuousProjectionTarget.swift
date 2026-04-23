//
//  SpecifiedContinuousProjectionTarget.swift
//  KurrentDB
//

/// Target for a named continuous projection, supporting both creation and control operations.
public struct SpecifiedContinuousProjectionTarget: ProjectionsTarget, ProjectionControlable {
    /// Name of the continuous projection.
    public let name: String
}

extension ProjectionsTarget where Self == SpecifiedContinuousProjectionTarget {
    /// Returns a target for the continuous projection with the given name.
    public static func continuous(name: String) -> SpecifiedContinuousProjectionTarget {
        .init(name: name)
    }
}
