//
//  ProjectionStream.swift
//  KurrentDB
//

/// Target representing a system projection stream.
public struct ProjectionStream: SpecifiedStreamTarget {
    /// Unique identifier for the projection stream.
    public private(set) var identifier: StreamIdentifier

    init(identifier: StreamIdentifier) {
        self.identifier = identifier
    }
}

extension StreamsTarget where Self == ProjectionStream {
    /// Creates a ``ProjectionStream`` for the `$et-<eventType>` category stream.
    public static func byEventType(_ eventType: String) -> ProjectionStream {
        .init(identifier: .init(name: "$et-\(eventType)"))
    }

    /// Creates a ``ProjectionStream`` for the `$ce-<prefix>` category stream.
    public static func byStream(prefix: String) -> ProjectionStream {
        .init(identifier: .init(name: "$ce-\(prefix)"))
    }
}
