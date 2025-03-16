//
//  ProjectionTarget.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/12.
//

public protocol ProjectionTarget: Sendable {}

public protocol NameSpecifiable {
    var name: String { get }
}

public struct SystemProjectionTarget: ProjectionTarget, NameSpecifiable, ProjectionEnable, ProjectionDisable, ProjectionResetable, ProjectionDescribable, ProjectionResulable {
    public enum Predefined: String, Sendable {
        /// Representation `$by_category`
        case byCategory = "$by_category"
        /// Representation  `$by_correlation_id`
        case byCorrelationId = "$by_correlation_id"
        /// Representation  `$by_event_type`
        case byEventType = "$by_event_type"
        /// Representation  `$stream_by_category`
        case streamByCategory = "$stream_by_category"
        /// Representation  `$streams`
        case streams = "$streams"
    }
    
    internal private(set) var predefined: Predefined
    
    public var name: String{
        get {
            predefined.rawValue
        }
    }
    
    internal init(predefined: Predefined) {
        self.predefined = predefined
    }
}

extension String: ProjectionCreatable, ProjectionTarget, NameSpecifiable, ProjectionEnable, ProjectionDisable, ProjectionResetable, ProjectionDescribable, ProjectionResulable, ProjectionUpdatable, ProjectionDeletable {
    public var name: String {
        self
    }
}

public protocol AllProjectionTargetProtocol {
    associatedtype Mode: ProjectionTargetMode
}


public struct AllProjectionTarget<Mode: ProjectionTargetMode>:  ProjectionTarget, AllProjectionTargetProtocol {
    let mode: Mode
}
