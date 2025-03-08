//
//  StreamTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/3/6.
//
import Foundation

/// Represents a stream target that can be sent (`StreamTarget`).
///
/// `StreamTarget` is a protocol that allows concrete types (such as `SpecifiedStream` and `AllStreams`)
/// to be used as stream targets.
///
/// ## Usage
///
/// You can use `specified(_:)` to create a specific stream or use `all` to get a predefined instance
/// representing all available streams:
///
/// ```swift
/// let specificStream = StreamTarget.specified("log.txt") // Specify by name
/// let specificStreamByIdentifier = StreamTarget.specified(StreamIdentifier(name: "log.txt", encoding: .utf8)) // Specify by identifier
///
/// let allStreams = StreamTarget.all // Represents all streams
/// ```
///
/// ### Extensions
/// - `SpecifiedStream`: Represents a specific stream and provides static methods for instantiation.
/// - `AllStreams`: Represents a placeholder for all streams.
/// - `AnyStreamTarget`: A generic stream target used when the type is not specified.
public protocol StreamTarget: Sendable {}

/// Represents a generic stream target that conforms to `StreamTarget`.
///
/// `AnyStreamTarget` is used in generic contexts where a specific stream type is not required.
public struct AnyStreamTarget: StreamTarget{}

//MARK: - Specified Stream

/// Represents a specific stream that conforms to `StreamTarget`.
///
/// `SpecifiedStream` is identified by a `StreamIdentifier` and can be instantiated using `StreamTarget.specified`.
public struct SpecifiedStream: StreamTarget {
    
    /// The identifier for the stream, represented as a `StreamIdentifier`.
    public private(set) var identifier: StreamIdentifier
    
    /// Initializes a `SpecifiedStream` instance.
    ///
    /// - Parameter identifier: The identifier for the stream.
    public init(identifier: StreamIdentifier) {
        self.identifier = identifier
    }
}

extension StreamTarget where Self == SpecifiedStream {
    
    /// Creates a `SpecifiedStream` using a `StreamIdentifier`.
    ///
    /// - Parameter identifier: The identifier for the stream.
    /// - Returns: A `SpecifiedStream` instance.
    public static func specified(_ identifier: StreamIdentifier)->SpecifiedStream{
        return .init(identifier: identifier)
    }

    /// Creates a `SpecifiedStream` identified by a name and encoding.
    ///
    /// - Parameters:
    ///   - name: The name of the stream.
    ///   - encoding: The encoding format of the stream, defaulting to `.utf8`.
    /// - Returns: A `SpecifiedStream` instance.
    public static func specified(_ name: String, encoding: String.Encoding = .utf8)->SpecifiedStream{
        return .init(identifier: .init(name: name, encoding: encoding))
    }
}


//MARK: - All Streams

/// Represents a placeholder for all streams that conform to `StreamTarget`.
///
/// `AllStreams` is a type that represents all available stream targets
/// and can be accessed using `StreamTarget.all`.
public struct AllStreams: StreamTarget {}


extension StreamTarget where Self == AllStreams {
    
    /// Creates a `SpecifiedStream` identified by a name and encoding.
    ///
    /// - Parameters:
    ///   - name: The name of the stream.
    ///   - encoding: The encoding format of the stream, defaulting to `.utf8`.
    /// - Returns: A `SpecifiedStream` instance.
    public static var all: AllStreams{
        return .init()
    }
}
