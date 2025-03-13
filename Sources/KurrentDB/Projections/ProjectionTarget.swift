//
//  ProjectionTarget.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/12.
//

public protocol ProjectionTarget: Sendable {}

public struct AllProjectionTarget: ProjectionTarget {
    internal let mode: Projection.Mode
}
public struct TransientProjectionTarget: ProjectionTarget { }
public struct ContinuousProjectionTarget: ProjectionTarget {
    internal let name: String
}
public struct OneTimeProjectionTarget: ProjectionTarget { }

public struct PredefinedProjection: ProjectionTarget {
    public enum Names: String, Sendable {
        /// Representation `$by_category`
        case byCategory = "$by_category"
        /// Representation  `$by_correlation_id`
        case byCorrelationId = "$by_correlation_id"
        /// Representation  `$by_event_type`
        case byEventType = "$by_event_type"
        /// Representation  `$stream_by_category`
        case streamByCategory = "$stream_by_category"
        /// Representation  `$streams`
        case streams = "$streams"
    }
    
    internal private(set) var name: Names
    internal private(set) var mode: Projection.Mode
    
    internal init(name: Names, mode: Projection.Mode) {
        self.name = name
        self.mode = mode
    }
}

extension ProjectionTarget where Self == AllProjectionTarget {
    public static func all(_ mode: Projection.Mode) -> Self {
        return .init(mode: mode)
    }
}

extension ProjectionTarget where Self == TransientProjectionTarget {
    @available(*, unavailable)
    public static var transient: Self {
        get{
            .init()
        }
    }
}

extension ProjectionTarget where Self == ContinuousProjectionTarget {
    
    public static func continuous(name: String)->Self{
        return .init(name: name)
    }
    
    public static func continuous(system: PredefinedProjection.Names)->Self{
        return .init(name: system.rawValue)
    }
}


extension ProjectionTarget where Self == OneTimeProjectionTarget {
    @available(*, unavailable)
    public static var oneTime: Self {
        get{
            .init()
        }
    }
}

