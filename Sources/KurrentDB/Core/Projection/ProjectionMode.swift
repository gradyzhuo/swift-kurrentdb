//
//  ProjectionMode.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/16.
//

/// A protocol defining the mode of a projection.
///
/// `ProjectionMode` specifies the operational mode of a projection, such as continuous or any.
/// It is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// - Note: Implementations include `ContinuousMode` and `AnyMode`.
public protocol ProjectionMode: Sendable {
    /// The mode of the projection, represented as a `Projection.Mode` value.
    var mode: Projection.Mode { get }
}

/// A mode indicating a continuous projection.
///
/// `ContinuousMode` represents a projection that runs continuously, processing events as they occur.
public struct ContinuousMode: ProjectionMode {
    /// The mode of the projection, fixed to `.continuous`.
    public let mode: Projection.Mode = .continuous
}

/// A mode indicating any projection type.
///
/// `AnyMode` represents a projection with no specific mode constraint, allowing flexibility in operation.
public struct AnyMode: ProjectionMode {
    /// The mode of the projection, fixed to `.any`.
    public let mode: Projection.Mode = .any
}

/// Provides a static property for creating a `ContinuousMode` instance.
extension ProjectionMode where Self == ContinuousMode {
    /// A static instance of `ContinuousMode`.
    public static var continuous: Self {
        return .init()
    }
}

/// Provides a static property for creating an `AnyMode` instance.
extension ProjectionMode where Self == AnyMode {
    /// A static instance of `AnyMode`.
    public static var any: Self {
        return .init()
    }
}

extension Projection {
    /// Defines the operational modes of a projection.
    ///
    /// `Mode` specifies how a projection operates, such as continuously or as a one-time task.
    /// It is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
    public enum Mode: String, Sendable {
        /// Represents a projection with no specific mode constraint.
        case any = "Any"
        
        /// Represents a transient projection (currently unavailable).
        case transient = "Transient"
        
        /// Represents a projection that runs continuously, processing events as they occur.
        case continuous = "Continuous"
        
        /// Represents a projection that runs once and then completes.
        case oneTime = "OneTime"
    }
}
