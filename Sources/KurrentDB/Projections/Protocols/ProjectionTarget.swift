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

/// A protocol for projection targets that have a specific name.
///
/// Conforming types must provide a `name` property to identify the projection.
public protocol NameSpecifiable {
    /// The name of the projection target.
    var name: String { get }
}

/// A predefined system projection target in an EventStore system.
///
/// `SystemProjectionTarget` represents built-in projections provided by EventStore, such as `$by_category`
/// or `$streams`. It supports enabling, disabling, resetting, describing, and retrieving results.
public struct SystemProjectionTarget: ProjectionTarget, NameSpecifiable, ProjectionEnable, ProjectionDisable, ProjectionResetable, ProjectionDescribable, ProjectionResulable {
    /// Predefined system projection types supported by EventStore.
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
    
    /// The predefined system projection type.
    internal private(set) var predefined: Predefined
    
    /// The name of the system projection.
    public var name: String {
        get {
            predefined.rawValue
        }
    }
    
    /// Initializes a `SystemProjectionTarget` with a predefined system projection.
    ///
    /// - Parameter predefined: The predefined system projection type (e.g., `.byCategory`).
    internal init(predefined: Predefined) {
        self.predefined = predefined
    }
}

/// Extends `String` to act as a custom projection target.
///
/// When used as a `String`, it represents a user-defined projection name and supports operations
/// like creation, updating, deletion, enabling, disabling, resetting, describing, and retrieving results.
extension String: ProjectionCreatable, ProjectionTarget, NameSpecifiable, ProjectionEnable, ProjectionDisable, ProjectionResetable, ProjectionDescribable, ProjectionResulable, ProjectionUpdatable, ProjectionDeletable {
    /// The name of the projection, represented by the string value.
    public var name: String {
        self
    }
}

/// A protocol for projection targets that apply to all projections with a specific mode.
///
/// Conforming types must specify an associated `Mode` that conforms to `ProjectionTargetMode`.
public protocol AllProjectionTargetProtocol {
    /// The mode type associated with the projection target.
    associatedtype Mode: ProjectionMode
}

/// A generic target representing all projections with a specific mode.
///
/// `AllProjectionTarget` is used to perform operations on all projections, with the behavior determined
/// by the associated `Mode` type conforming to `ProjectionTargetMode`.
public struct AllProjectionTarget<Mode: ProjectionMode>: ProjectionTarget, AllProjectionTargetProtocol {
    /// The mode defining the behavior of the all-projection target.
    let mode: Mode
}
