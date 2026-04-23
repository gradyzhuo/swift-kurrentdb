//
//  Projection.Status.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/14.
//

extension Projection {
    /// Composite status value reported by the server for a projection.
    public struct Status: Sendable {
        /// Raw status string as returned by the server.
        public typealias RawValue = String
        /// Underlying status string, which may contain multiple slash-separated state names.
        public let rawValue: String

        /// Parsed list of individual status names extracted from the raw value.
        public var names: [Name] {
            rawValue.replacing(" results", with: "")
                .split(separator: "/")
                .compactMap {
                    Name(rawValue: String($0))
                }
        }

        /// Creates a status from the raw server string.
        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }
}

extension Projection.Status {
    /// Individual named state component of a projection's status.
    public enum Name: String, Sendable {
        /// Projection is actively processing events.
        case running = "Running"
        /// Projection has been stopped cleanly.
        case stopped = "Stopped"
        /// Projection encountered an unrecoverable error.
        case faulted = "Faulted"
        /// Projection has been created but not yet started.
        case initial = "Initial"
        /// Projection is writing results.
        case writing = "Writing"
        /// Projection finished processing all events (one-time mode).
        case completed = "Completed"
        /// Projection is suspended and not currently processing.
        case suspended = "Suspended"
        /// Projection is requesting its persisted state to be loaded.
        case loadStateRequested = "LoadStateRequested"
        /// Projection's persisted state has been loaded successfully.
        case stateLoaded = "StateLoaded"
        /// Projection has subscribed to the event stream.
        case subscribed = "Subscribed"
        /// Projection encountered an error while stopping.
        case faultedStopping = "FaultedStopping"
        /// Projection is in the process of stopping.
        case stopping = "Stopping"
        /// Projection is completing the current processing phase.
        case completingPhase = "CompletingPhase"
        /// Current processing phase has completed.
        case phaseCompleted = "PhaseCompleted"
        /// Projection was aborted without writing a checkpoint.
        case aborted = "Aborted"
        /// Projection is faulted but has been re-enabled.
        case faultedEnabled = "Faulted (Enabled)"
    }

    func contains(_ status: Name) -> Bool {
        contains([status])
    }

    func contains(_ statuses: [Name]) -> Bool {
        Set<Name>(names).isSuperset(of: statuses)
    }
}
