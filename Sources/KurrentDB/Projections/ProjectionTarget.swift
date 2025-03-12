//
//  ProjectionTarget.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/12.
//

public protocol ProjectionTarget: Sendable {}

public struct AllProjectionTarget: ProjectionTarget { }
public struct TransientProjectionTarget: ProjectionTarget { }
public struct ContinuousProjectionTarget: ProjectionTarget { }
public struct OneTimeProjectionTarget: ProjectionTarget { }



public struct SpecifiedProjection: ProjectionTarget {
    public private(set) var name: String
    
    internal init(name: String) {
        self.name = name
    }
}

public struct PredefinedProjection: ProjectionTarget {
    public enum Names: String, Sendable {
        case byCategory = "$by_category"
        case byCorrelationId = "$by_correlation_id"
        case byEventType = "$by_event_type"
        case streamByCategory = "$stream_by_category"
        case streams = "$streams"
    }
    
    public private(set) var name: Names
    
    internal init(name: Names) {
        self.name = name
    }
}

extension ProjectionTarget where Self == AllProjectionTarget {
    public static var all: Self {
        get{
            .init()
        }
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
    public static var continuous: Self {
        get{
            .init()
        }
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



extension ProjectionTarget where Self == SpecifiedProjection {
    
    public static func specified(_ name: String) -> Self {
        return .init(name: name)
    }
    
}

extension ProjectionTarget where Self == PredefinedProjection {
    public static func system(_ name: Self.Names) -> Self {
        return .init(name: name)
    }
}
