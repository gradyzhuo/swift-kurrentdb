//
//  ProjectionTarget.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/12.
//

/// A protocol representing a target for projections in an EventStore system.
///
/// `ProjectionTarget` defines a common interface for types that can be used as targets for projections.
/// It is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// - Note: Implementations include `SystemProjectionTarget`, `String`, and `AllProjectionTarget`.
public protocol ProjectionTarget: Sendable {}

public struct NameTarget: ProjectionTarget {
    public enum Predefined: String, Sendable {
        /// Represents the `$by_category` system projection.
        case byCategory = "$by_category"
        /// Represents the `$by_correlation_id` system projection.
        case byCorrelationId = "$by_correlation_id"
        /// Represents the `$by_event_type` system projection.
        case byEventType = "$by_event_type"
        /// Represents the `$stream_by_category` system projection.
        case streamByCategory = "$stream_by_category"
        /// Represents the `$streams` system projection.
        case streams = "$streams"
    }
    
    public let name: String
    
    public init(name: String){
        self.name = name
    }
    
    public init(predefined: Predefined){
        self.name = predefined.rawValue
    }

}


/// A generic target representing all projections.
///
/// `AnyTarget` is used to perform operations on all projections, with the behavior determined
public struct AnyTarget: ProjectionTarget {
    /// The mode defining the behavior of the all-projection target.

}


