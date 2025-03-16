//
//  ProjectionTargetMode.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/16.
//

public protocol ProjectionTargetMode: Sendable{
    var mode: Projection.Mode { get }
}

public struct ContinuousMode: ProjectionTargetMode {
    public let mode: Projection.Mode = .continuous
}

public struct AnyMode: ProjectionTargetMode {
    public let mode: Projection.Mode = .any
}

extension ProjectionTargetMode where Self == ContinuousMode {
    public static var continuous: Self {
        return .init()
    }
}


extension ProjectionTargetMode where Self == AnyMode {
    public static var any: Self {
        return .init()
    }
}
