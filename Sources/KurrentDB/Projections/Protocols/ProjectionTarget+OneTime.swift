//
//  ProjectionTarget+OneTime.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/5.
//

/// A generic target representing one time projections.
///
/// `OneTimeTarget` is used to perform operations on all projections, with the behavior determined
public struct OneTimeTarget: ProjectionTarget { }

/// Extension providing static methods to create `ProjectionStream` instances.
extension ProjectionTarget where Self == OneTimeTarget {
    public static var onetime: OneTimeTarget{
        get{
            .init()
        }
    }
}
