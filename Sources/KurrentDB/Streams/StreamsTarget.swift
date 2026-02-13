//
//  StreamsTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/3/6.
//

import Foundation

/// Represents a stream target that can be sent (`StreamsTarget`).
///
/// `StreamsTarget` is a protocol that allows concrete types (such as `SpecifiedStream` and `AllStreams`)
/// to be used as stream targets.
///
/// ## Usage
///
/// You can use `specified(_:)` to create a specific stream or use `all` to get a predefined instance
/// representing all available streams:
///
/// ```swift
/// let specificStream = StreamsTarget.specified("log.txt") // Specify by name
/// let specificStreamByIdentifier = StreamsTarget.specified(StreamIdentifier(name: "log.txt", encoding: .utf8)) // Specify by identifier
/// let allStreams = StreamsTarget.all // Represents all streams
/// ```
///
/// - Note: This protocol is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// ### Topics
/// #### Extensions
/// - ``SpecifiedStream``: Represents a specific stream and provides static methods for instantiation.
/// - ``AllStreams``: Represents a placeholder for all streams.
/// - ``AnyStreamTarget``: A generic stream target used when the type is not specified.
public protocol StreamsTarget: Sendable {}

/// Represents a generic stream target that conforms to `StreamsTarget`.
///
/// `AnyStreamTarget` is used in generic contexts where a specific stream type is not required.
public struct AnyStreamTarget: StreamsTarget {}

/// A protocol for stream targets that have a specific identifier.
///
/// Conforming types must provide a `StreamIdentifier` to uniquely identify the stream.
public protocol SpecifiedStreamTarget: StreamsTarget {
    /// The identifier for the stream.
    var identifier: StreamIdentifier { get }
}

// MARK: - Specified Stream

/// Represents a specific stream that conforms to `StreamsTarget`.
///
/// `SpecifiedStream` is identified by a `StreamIdentifier` and can be instantiated using `StreamsTarget.specified`.
public struct SpecifiedStream: SpecifiedStreamTarget {
    /// The identifier for the stream, represented as a `StreamIdentifier`.
    public private(set) var identifier: StreamIdentifier

    /// Initializes a `SpecifiedStream` instance.
    ///
    /// - Parameter identifier: The identifier for the stream.
    init(identifier: StreamIdentifier) {
        self.identifier = identifier
    }
}

/// Extension providing static methods to create `SpecifiedStream` instances.
extension StreamsTarget where Self == SpecifiedStream {
    /// Creates a `SpecifiedStream` using a `StreamIdentifier`.
    ///
    /// - Parameter identifier: The identifier for the stream.
    /// - Returns: A `SpecifiedStream` instance.
    public static func specified(_ identifier: StreamIdentifier) -> SpecifiedStream {
        .init(identifier: identifier)
    }

    /// Creates a `SpecifiedStream` identified by a name and encoding.
    ///
    /// - Parameters:
    ///   - name: The name of the stream.
    ///   - encoding: The encoding format of the stream, defaulting to `.utf8`.
    /// - Returns: A `SpecifiedStream` instance.
    public static func specified(_ name: String, encoding: String.Encoding = .utf8) -> SpecifiedStream {
        .init(identifier: .init(name: name, encoding: encoding))
    }
}

// MARK: - MultiStreams
public struct MultiStreams: StreamsTarget {}
extension StreamsTarget where Self == MultiStreams{
    public static var multiple: MultiStreams {
        .init()
    }
}


// MARK: - All Streams

/// Represents a placeholder for all streams that conform to `StreamsTarget`.
///
/// `AllStreams` is a type that represents all available stream targets
/// and can be accessed using `StreamsTarget.all`.
public struct AllStreams: StreamsTarget {}

/// Extension providing a static property to access an `AllStreams` instance.
extension StreamsTarget where Self == AllStreams {
    /// Provides an instance representing all streams.
    ///
    /// - Returns: An `AllStreams` instance.
    public static var all: AllStreams {
        .init()
    }
}

/// Allows `SpecifiedStream` to be initialized with a string literal.
extension SpecifiedStream: ExpressibleByStringLiteral {
    public typealias StringLiteralType = String

    /// Initializes a `SpecifiedStream` from a string literal.
    ///
    /// - Parameter value: The string literal representing the stream name.
    public init(stringLiteral value: String) {
        identifier = .init(name: value)
    }
}

// MARK: - String Conformance

/// Extends `String` to conform to `SpecifiedStreamTarget`.
extension String: SpecifiedStreamTarget {
    /// The identifier for the stream, derived from the string value.
    public var identifier: StreamIdentifier {
        .init(name: self)
    }
}

// MARK: - Projection Stream

/// Represents a projection stream that conforms to `StreamsTarget`.
///
/// `ProjectionStream` is identified by a `StreamIdentifier` and can be instantiated using specific projection methods.
public struct ProjectionStream: SpecifiedStreamTarget {
    /// The identifier for the stream, represented as a `StreamIdentifier`.
    public private(set) var identifier: StreamIdentifier

    /// Initializes a `ProjectionStream` instance.
    ///
    /// - Parameter identifier: The identifier for the stream.
    init(identifier: StreamIdentifier) {
        self.identifier = identifier
    }
}

/// Extension providing static methods to create `ProjectionStream` instances.
extension StreamsTarget where Self == ProjectionStream {
    /// Creates a `ProjectionStream` based on an event type.
    ///
    /// - Parameter eventType: The event type to project, prefixed with "$et-".
    /// - Returns: A `ProjectionStream` instance.
    public static func byEventType(_ eventType: String) -> ProjectionStream {
        .init(identifier: .init(name: "$et-\(eventType)"))
    }

    /// Creates a `ProjectionStream` based on a stream prefix.
    ///
    /// - Parameter prefix: The stream prefix to project, prefixed with "$ce-".
    /// - Returns: A `ProjectionStream` instance.
    public static func byStream(prefix: String) -> ProjectionStream {
        .init(identifier: .init(name: "$ce-\(prefix)"))
    }
}
