//
//  ProjectionTarget+OneTime.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A generic target representing transient projections.
///
/// `TransientTarget` is used to perform operations on all projections, with the behavior determined
public struct TransientTarget: ProjectionTarget {
    let name: String
}

/// Extension providing static methods to create `ProjectionStream` instances.
extension ProjectionTarget where Self == TransientTarget {
    public static func transient(name: String) -> TransientTarget{
        return .init(name: name)
    }
}
