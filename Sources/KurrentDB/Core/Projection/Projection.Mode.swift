//
//  ProjectionMode.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/16.
//

extension Projection {
    /// Operational mode of a projection.
    public enum Mode: String, Sendable {
        /// No specific mode constraint; matches any projection mode.
        case any = "Any"

        /// Runs server-side without a checkpoint; discarded when the server restarts.
        case transient = "Transient"

        /// Runs indefinitely, processing events as they arrive.
        case continuous = "Continuous"

        /// Runs once over existing events and then stops.
        case oneTime = "OneTime"
    }
}
