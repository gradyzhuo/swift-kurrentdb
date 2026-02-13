//
//  ProjectionsTarget+OneTime.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A generic target representing continuous projections.
///
/// `ContinuousTarget` is used to perform operations on all projections, with the behavior determined
public struct ContinuousTarget: ProjectionsTarget, ProjectionControlable {
    public let name: String
}

