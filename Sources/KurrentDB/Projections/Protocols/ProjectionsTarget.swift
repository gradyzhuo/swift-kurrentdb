//
//  ProjectionsTarget.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/12.
//

/// A protocol representing a target for projections in an EventStore system.
///
/// `ProjectionsTarget` defines a common interface for types that can be used as targets for projections.
/// It is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// - Note: Implementations include `SystemProjectionTarget`, `String`, and `AllProjectionTarget`.
public protocol ProjectionsTarget: Sendable {}

/// Extension providing static methods to create `ProjectionStream` instances.
extension ProjectionsTarget {
    public static func named(_ name: String) -> NameTarget {
        return .init(name: name)
    }

    public static func continuous(name: String) -> ContinuousTarget{
        return .init(name: name)
    }

    public static var onetime: OneTimeTarget{
        get{
            .init()
        }
    }

    public static func transient(name: String) -> TransientTarget{
        return .init(name: name)
    }

    public static var any: AnyProjectionsTarget{
        get{
            .init()
        }
    }

}






