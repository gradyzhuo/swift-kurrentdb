//
//  Projection.Status.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/14.
//

extension Projection {
    public struct Status: OptionSet, Sendable {
        public enum Name: String, Sendable {
            case running = "Running"
            case stopped = "Stopped"
            case faulted = "Faulted"
            case initial = "Initial"
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
        
        public typealias RawValue = Int
        public let rawValue: Int
        
        public init?(name rawValue: String){
            self.init()
            for nameValue in rawValue.split(separator: "/") {
                guard let name = Name(rawValue: String(nameValue)) else {
                    return nil
                }
                self.insert(.init(name: name))
            }
        }
        
        public init(name: Name){
            switch name {
            case .running:
                self = .running
            case .stopped:
                self = .stopped
            case .faulted:
                self = .faulted
            case .initial:
                self = .initial
            case .suspended:
                self = .suspended
            case .loadStateRequested:
                self = .loadStateRequested
            case .stateLoaded:
                self = .stateLoaded
            case .subscribed:
                self = .subscribed
            case .faultedStopping:
                self = [.faulted, .stopping]
            case .stopping:
                self = .stopping
            case .completingPhase:
                self = .completingPhase
            case .phaseCompleted:
                self = .phaseCompleted
            case .aborted:
                self = .aborted
            case .faultedEnabled:
                self = .faulted
            }
        }
        
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
        
        public static let running = Status(rawValue: 1 << 0)
        public static let stopped = Status(rawValue: 1 << 1)
        public static let faulted = Status(rawValue: 1 << 2)
        public static let initial = Status(rawValue: 1 << 3)
        public static let suspended = Status(rawValue: 1 << 4)
        public static let loadStateRequested = Status(rawValue: 1 << 5)
        public static let stateLoaded = Status(rawValue: 1 << 6)
        public static let subscribed = Status(rawValue: 1 << 7)
        public static let faultedStopping = Status(rawValue: 1 << 8)
        public static let stopping = Status(rawValue: 1 << 9)
        public static let completingPhase = Status(rawValue: 1 << 10)
        public static let phaseCompleted = Status(rawValue: 1 << 11)
        public static let aborted = Status(rawValue: 1 << 12)
    }
    
}
