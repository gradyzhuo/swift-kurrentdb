//
//  NameTarget.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/13.
//

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
