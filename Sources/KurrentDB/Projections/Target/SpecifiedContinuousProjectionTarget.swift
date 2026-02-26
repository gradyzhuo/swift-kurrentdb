//
//  SpecifiedContinuousProjectionTarget.swift
//  KurrentDB
//

/// A target representing a named continuous projection.
///
/// Supports both creation and control operations (enable, disable, update, etc.).
public struct SpecifiedContinuousProjectionTarget: ProjectionsTarget, ProjectionControlable {
    public let name: String
}

extension ProjectionsTarget where Self == SpecifiedContinuousProjectionTarget{
    /// Creates a target for a continuous projection with the given name.
    public static func continuous(name: String) -> SpecifiedContinuousProjectionTarget {
        .init(name: name)
    }
}
