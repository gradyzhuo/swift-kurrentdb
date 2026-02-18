//
//  ProjectionTarget+Transient.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A generic target representing transient projections.
///
/// `SpecifiedTransientProjectionTarget` is used to perform operations on all projections, with the behavior determined
public struct SpecifiedTransientProjectionTarget: ProjectionsTarget, ProjectionControlable {
    public let name: String
}
