//
//  ProjectionTarget+OneTime.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A generic target representing continuous projections.
///
/// `ContinuousTarget` is used to perform operations on all projections, with the behavior determined
public struct ContinuousTarget: ProjectionTarget {
    let name: String
}

/// Extension providing static methods to create `ProjectionStream` instances.
extension ProjectionTarget where Self == ContinuousTarget {
    public static func continuous(name: String) -> ContinuousTarget{
        return .init(name: name)
    }
}
