//
//  PersistentSubscriptionStreamSelection.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/30.
//

import GRPCEncapsulates
import SwiftProtobuf

/// Identifies the stream that a persistent subscription targets.
public protocol PersistentSubscriptionStreamSelection: Sendable {
    associatedtype Cursor: Sendable
    /// Identifier of the target stream.
    var streamIdentifier: StreamIdentifier { get }
}

extension PersistentSubscriptionStreamSelection where Self == PersistentSubscriptionSpecifiedStream {
    /// Creates a selection targeting a specific named stream.
    public static func specified(_ streamIdentifier: StreamIdentifier) -> Self {
        .init(streamIdentifier: streamIdentifier)
    }
}

extension PersistentSubscriptionStreamSelection where Self == PersistentSubscriptionStreamAll {
    /// Creates a selection targeting the global `$all` stream.
    public static var all: Self {
        .init()
    }
}

/// A stream selection that targets a specific named stream.
public struct PersistentSubscriptionSpecifiedStream: PersistentSubscriptionStreamSelection {
    public typealias Cursor = RevisionCursor
    /// Identifier of the named stream.
    public let streamIdentifier: StreamIdentifier

    package init(streamIdentifier: StreamIdentifier) {
        self.streamIdentifier = streamIdentifier
    }
}

/// A stream selection that targets the global `$all` stream.
public struct PersistentSubscriptionStreamAll: PersistentSubscriptionStreamSelection {
    public typealias Cursor = PositionCursor
    /// Always returns the well-known `$all` stream identifier.
    public var streamIdentifier: StreamIdentifier {
        .all
    }
}
