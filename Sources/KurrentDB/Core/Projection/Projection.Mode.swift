//
//  ProjectionMode.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/16.
//

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
