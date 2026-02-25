//
//  ProjectionTarget+Transient.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A target representing a named transient projection.
///
/// Use `SpecifiedTransientProjectionTarget` when you know the projection name upfront.
/// It supports both creation and control operations (enable, disable, delete, etc.).
public struct SpecifiedTransientProjectionTarget: ProjectionsTarget, ProjectionControlable {
    public let name: String
}

/// A target representing a transient projection where the name is provided at creation time.
///
/// Use `UnspecifiedTransientProjectionTarget` when you want to create transient projections
/// by passing the name directly to `create(name:query:)` rather than at target construction.
/// This target does not conform to `ProjectionControlable` — use ``SpecifiedTransientProjectionTarget``
/// or ``NameTarget`` for control operations.
public struct UnspecifiedTransientProjectionTarget: ProjectionsTarget {
    public init() {}
}
