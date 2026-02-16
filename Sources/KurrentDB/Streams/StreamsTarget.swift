//
//  StreamsTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/3/6.
//

import Foundation

/// A protocol representing a target for stream operations in KurrentDB.
///
/// A **target** serves two key purposes in the Streams API:
///
/// ## 1. Specifies the Operation Scope (Where)
///
/// The target identifies which streams the operation applies to:
/// - `SpecifiedStream`: Operates on a specific named stream
/// - `AllStreams`: Operates on the global `$all` stream containing all events
/// - `MultiStreams`: Operates on multiple streams simultaneously
/// - `ProjectionStream`: Operates on system projection streams
///
/// ## 2. Constrains Available Operations (What)
///
/// Through protocol composition, different target types enable different capabilities:
/// - Targets conforming to `SpecifiedStreamTarget` support append, read, delete, and subscription operations
/// - `AllStreams` only supports read and subscription operations (cannot append to `$all`)
/// - `MultiStreams` only supports batch append operations
/// - The type system prevents invalid operations at compile time
///
/// ## Type Safety
///
/// This design provides compile-time guarantees that operations are only performed on appropriate stream types:
///
/// ```swift
/// // Target specifies: operate on "orders" stream (where)
/// // Target constrains: can append, read, delete (what)
/// let stream = Streams(target: .specified("orders"), ...)
/// try await stream.append(events: [...])     // ✓ Allowed
/// try await stream.readStream()              // ✓ Allowed
///
/// // Target specifies: operate on $all (where)
/// // Target constrains: can only read/subscribe (what)
/// let allStreams = Streams(target: .all, ...)
/// try await allStreams.readStream()          // ✓ Allowed
/// try await allStreams.append(events: [...]) // ✗ Compile error - no such method
///
/// // Target specifies: multiple streams (where)
/// // Target constrains: only batch append (what)
/// let multiStreams = Streams(target: .multiple, ...)
/// try await multiStreams.append(events: [...])  // ✓ Allowed (batch)
/// try await multiStreams.readStream()           // ✗ Compile error - no such method
/// ```
///
/// ## Usage
///
/// Create targets using static factory methods:
///
/// ```swift
/// // Specific stream by name
/// let orders = StreamsTarget.specified("orders")
///
/// // Specific stream by identifier
/// let identifier = StreamIdentifier(name: "orders", encoding: .utf8)
/// let ordersById = StreamsTarget.specified(identifier)
///
/// // All streams
/// let all = StreamsTarget.all
///
/// // Multiple streams
/// let multi = StreamsTarget.multiple
///
/// // Projection streams
/// let byType = StreamsTarget.byEventType("OrderCreated")
/// let byPrefix = StreamsTarget.byStream(prefix: "order")
/// ```
///
/// - Note: This protocol is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// - SeeAlso: `SpecifiedStreamTarget`, `AllStreams`, `MultiStreams`, `ProjectionStream`
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
extension StreamsTarget where Self == MultiStreams {
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
