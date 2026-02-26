//
//  NameTarget.swift
//  KurrentDB
//

/// A target for a specific named projection, regardless of its mode.
///
/// Use this when you want to address a projection by name for control operations
/// (enable, disable, update, delete, reset) without constraining it to a particular type.
public struct NameTarget: ProjectionsTarget, ProjectionControlable {
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

    public init(name: String) {
        self.name = name
    }

    public init(predefined: Predefined) {
        name = predefined.rawValue
    }
}

extension ProjectionsTarget where Self == NameTarget {
    /// Creates a target for a specific projection identified by name, regardless of its mode.
    public static func anyMode(name: String) -> Self {
        .init(name: name)
    }
}
