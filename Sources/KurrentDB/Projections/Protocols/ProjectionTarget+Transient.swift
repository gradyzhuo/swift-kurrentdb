//
//  ProjectionsTarget+OneTime.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A generic target representing transient projections.
///
/// `TransientTarget` is used to perform operations on all projections, with the behavior determined
public struct TransientTarget: ProjectionsTarget, ProjectionControlable {
    public let name: String
}


