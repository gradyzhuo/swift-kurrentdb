//
//  Projection.Status.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/14.
//

extension Projection {
    public struct Status: Sendable {
        public typealias RawValue = String
        public let rawValue: String

        public var names: [Name]{
            get{
                return rawValue.replacing(" results", with: "")
                        .split(separator: "/")
                        .compactMap{
                            Name(rawValue: String($0))
                        }
            }
        }
        
        public init(rawValue: String){
            self.rawValue = rawValue
        }
    }
}

extension Projection.Status {
    public enum Name: String, Sendable {
        case running = "Running"
        case stopped = "Stopped"
        case faulted = "Faulted"
        case initial = "Initial"
        case writing = "Writing"
        case completed = "Completed"
        case suspended = "Suspended"
        case loadStateRequested = "LoadStateRequested"
        case stateLoaded = "StateLoaded"
        case subscribed = "Subscribed"
        case faultedStopping = "FaultedStopping"
        case stopping = "Stopping"
        case completingPhase = "CompletingPhase"
        case phaseCompleted = "PhaseCompleted"
        case aborted = "Aborted"
        case faultedEnabled = "Faulted (Enabled)"
    }
    
    
    func contains(_ status: Name) -> Bool {
        return contains([status])
    }
    
    func contains(_ statuses: [Name]) -> Bool {
        return Set<Name>.init(names).isSuperset(of: statuses)
    }

}

