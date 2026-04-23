//
//  SpecifiedTransientProjectionTarget.swift
//  KurrentDB
//

/// Target for a named transient projection, supporting both creation and control operations.
public struct SpecifiedTransientProjectionTarget: ProjectionsTarget, ProjectionControlable {
    /// Name of the transient projection.
    public let name: String
}

extension ProjectionsTarget where Self == SpecifiedTransientProjectionTarget {
    /// Returns a target for the transient projection with the given name.
    public static func transient(name: String) -> SpecifiedTransientProjectionTarget {
        .init(name: name)
    }
}
