//
//  PersistentSubscriptionTarget.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/3/6.
//

import Foundation

/// Represents a target for persistent subscriptions that can be sent.
///
/// `PersistentSubscriptionTarget` is a protocol that allows concrete types (such as `Specified` and `All`)
/// to be used as targets for persistent subscriptions.
///
/// ## Usage
///
/// You can use `specified(_:group:)` to create a specific stream subscription target or use `all(group:)`
/// to get a predefined instance representing all available streams:
///
/// ```swift
/// let specificStream = PersistentSubscriptionTarget.specified("log.txt", group: "myGroup") // Specify by name
/// let specificStreamByIdentifier = PersistentSubscriptionTarget.specified(StreamIdentifier(name: "log.txt", encoding: .utf8), group: "myGroup") // Specify by identifier
/// let allStreams = PersistentSubscriptionTarget.all(group: "myGroup") // Represents all streams
/// ```
///
/// - Note: This protocol is marked as `Sendable`, ensuring it can be safely used across concurrency contexts.
///
/// ### Topics
/// #### Extensions
/// - ``PersistentSubscription.Specified``: Represents a specific stream subscription target.
/// - ``PersistentSubscription.All``: Represents a placeholder for all streams.
/// - ``PersistentSubscription.AnyTarget``: A generic subscription target used when the type is not specified.
public protocol PersistentSubscriptionTarget: Sendable {}

extension PersistentSubscription {
    /// Represents a generic subscription target that conforms to `PersistentSubscriptionTarget`.
    ///
    /// `AnyTarget` is used in generic contexts where a specific subscription target type is not required.
    public struct AnyTarget: PersistentSubscriptionTarget {}
    
    // MARK: - Specified Stream

    /// Represents a specific stream target for persistent subscriptions.
    ///
    /// `Specified` is identified by a `StreamIdentifier` and a group name, and can be instantiated
    /// using `PersistentSubscriptionTarget.specified`.
    public struct Specified: PersistentSubscriptionTarget {
        
        /// The identifier for the stream, represented as a `StreamIdentifier`.
        public private(set) var identifier: StreamIdentifier
        
        /// The group name for the persistent subscription.
        public private(set) var group: String
        
        /// Initializes a `Specified` persistent subscription target instance.
        ///
        /// - Parameters:
        ///   - identifier: The identifier for the stream.
        ///   - group: The group name for the persistent subscription.
        public init(identifier: StreamIdentifier, group: String) {
            self.identifier = identifier
            self.group = group
        }
    }
    
    // MARK: - All Streams

    /// Represents a placeholder for all streams in a persistent subscription.
    ///
    /// `All` represents all available stream targets for a subscription and can be accessed
    /// using `PersistentSubscriptionTarget.all(group:)`.
    public struct AllGroup: PersistentSubscriptionTarget {
        /// The group name for the persistent subscription.
        public private(set) var group: String
        
        /// Initializes an `All` persistent subscription target instance.
        ///
        /// - Parameter group: The group name for the persistent subscription.
        public init(group: String) {
            self.group = group
        }
    }
    
    public struct AllStream: PersistentSubscriptionTarget {
        /// The group name for the persistent subscription.
        public private(set) var streamIdentifier: StreamIdentifier
        
        /// Initializes an `All` persistent subscription target instance.
        ///
        /// - Parameter group: The group name for the persistent subscription.
        public init(stream streamIdentifier: StreamIdentifier) {
            self.streamIdentifier = streamIdentifier
        }
    }
    
    public struct All: PersistentSubscriptionTarget {
        
    }
}

/// Extension providing static methods to create `Specified` persistent subscription targets.
extension PersistentSubscriptionTarget where Self == PersistentSubscription.Specified {
    
    /// Creates a `Specified` target using a `StreamIdentifier`.
    ///
    /// - Parameters:
    ///   - identifier: The identifier for the stream.
    ///   - group: The group name for the persistent subscription.
    /// - Returns: A `PersistentSubscription.Specified` instance.
    public static func specified(_ identifier: StreamIdentifier, group: String) -> PersistentSubscription.Specified {
        return .init(identifier: identifier, group: group)
    }

    /// Creates a `Specified` target identified by a name and encoding.
    ///
    /// - Parameters:
    ///   - name: The name of the stream.
    ///   - encoding: The encoding format of the stream, defaulting to `.utf8`.
    ///   - group: The group name for the persistent subscription.
    /// - Returns: A `PersistentSubscription.Specified` instance.
    public static func specified(_ name: String, encoding: String.Encoding = .utf8, group: String) -> PersistentSubscription.Specified {
        return .init(identifier: .init(name: name, encoding: encoding), group: group)
    }
}

/// Extension providing a static method to create an `All` persistent subscription target.
extension PersistentSubscriptionTarget where Self == PersistentSubscription.AllStream {
    
    public static func stream(_ identifier: StreamIdentifier) -> PersistentSubscription.AllStream {
        return .init(stream: identifier)
    }
    
    public static func stream(_ name: String) -> PersistentSubscription.AllStream {
        return .init(stream: .init(name: name))
    }
    
}

/// Extension providing a static method to create an `All` persistent subscription target.
extension PersistentSubscriptionTarget where Self == PersistentSubscription.AllGroup {
    
    /// Creates an `AllStream` target representing all streams for a persistent subscription.
    ///
    /// - Parameter group: The group name for the persistent subscription.
    /// - Returns: A `PersistentSubscription.All` instance.
    public static func group(_ group: String) -> PersistentSubscription.AllGroup {
        return .init(group: group)
    }
    
}



/// Extension providing a static method to create an `All` persistent subscription target.
extension PersistentSubscriptionTarget where Self == PersistentSubscription.All {
    /// Creates an `All` target representing all streams for a persistent subscription.
    ///
    /// - Parameter group: The group name for the persistent subscription.
    /// - Returns: A `PersistentSubscription.All` instance.
    public static var all: PersistentSubscription.All {
        return .init()
    }
}
