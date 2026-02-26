//
//  ProjectionStream.swift
//  KurrentDB
//

/// Represents a system projection stream.
public struct ProjectionStream: SpecifiedStreamTarget {
    /// The identifier for the stream.
    public private(set) var identifier: StreamIdentifier

    init(identifier: StreamIdentifier) {
        self.identifier = identifier
    }
}

extension StreamsTarget where Self == ProjectionStream {
    /// Creates a `ProjectionStream` scoped to events of a specific type.
    public static func byEventType(_ eventType: String) -> ProjectionStream {
        .init(identifier: .init(name: "$et-\(eventType)"))
    }

    /// Creates a `ProjectionStream` scoped to streams with a specific prefix.
    public static func byStream(prefix: String) -> ProjectionStream {
        .init(identifier: .init(name: "$ce-\(prefix)"))
    }
}
