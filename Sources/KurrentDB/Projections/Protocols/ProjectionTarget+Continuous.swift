//
//  ProjectionTarget+Continuous.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A target representing a named continuous projection.
///
/// Use `SpecifiedContinuousProjectionTarget` when you know the projection name upfront.
/// It supports both creation and control operations (enable, disable, update, etc.).
public struct SpecifiedContinuousProjectionTarget: ProjectionsTarget, ProjectionControlable {
    public let name: String
}

/// A target representing a continuous projection where the name is provided at creation time.
///
/// Use `UnspecifiedContinuousProjectionTarget` when you want to create continuous projections
/// by passing the name directly to `create(name:query:)` rather than at target construction.
/// This target does not conform to `ProjectionControlable` — use ``SpecifiedContinuousProjectionTarget``
/// or ``NameTarget`` for control operations.
public struct UnspecifiedContinuousProjectionTarget: ProjectionsTarget {}
