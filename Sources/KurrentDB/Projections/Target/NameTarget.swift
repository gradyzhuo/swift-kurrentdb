//
//  NameTarget.swift
//  KurrentDB
//

/// Target for a named projection, independent of its operational mode.
public struct NameTarget: ProjectionsTarget, ProjectionControlable {
    /// Well-known built-in system projections.
    public enum Predefined: String, Sendable {
        /// The `$by_category` system projection.
        case byCategory = "$by_category"
        /// The `$by_correlation_id` system projection.
        case byCorrelationId = "$by_correlation_id"
        /// The `$by_event_type` system projection.
        case byEventType = "$by_event_type"
        /// The `$stream_by_category` system projection.
        case streamByCategory = "$stream_by_category"
        /// The `$streams` system projection.
        case streams = "$streams"
    }

    /// Name of the target projection.
    public let name: String

    /// Creates a target for the projection with the given name.
    public init(name: String) {
        self.name = name
    }

    /// Creates a target for a predefined system projection.
    public init(predefined: Predefined) {
        name = predefined.rawValue
    }
}

extension ProjectionsTarget where Self == NameTarget {
    /// Returns a target for the named projection, regardless of its mode.
    public static func anyMode(name: String) -> Self {
        .init(name: name)
    }
}
