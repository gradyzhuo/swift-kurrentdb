//
//  SpecifiedTransientProjectionTarget.swift
//  KurrentDB
//

/// A target representing a named transient projection.
///
/// Supports both creation and control operations (enable, disable, delete, etc.).
public struct SpecifiedTransientProjectionTarget: ProjectionsTarget, ProjectionControlable {
    public let name: String
}

extension ProjectionsTarget {
    /// Creates a target for a transient projection with the given name.
    public static func transient(name: String) -> SpecifiedTransientProjectionTarget {
        .init(name: name)
    }
}
