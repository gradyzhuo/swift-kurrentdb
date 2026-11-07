//
//  Streams.Subscription.Message.swift
//  KurrentStreams
//
//  What a subscription delivers: an event, or a notification about the subscription itself,
//  each notification with the server's time and the point to resume from.
//

import Foundation

extension Streams.Subscription {
    /// What the server sends on a subscription: an event, or a notification about the
    /// subscription itself.
    ///
    /// New cases are major-release changes while toolchains without `@nonexhaustive` (Swift 6.0 to 6.2.2)
    /// are supported; on Swift 6.2.3 and later it makes an exhaustive switch in another package require
    /// `@unknown default`, which is the recommended form everywhere.
    #if hasAttribute(nonexhaustive)
    @nonexhaustive
    #endif
    public enum Message: Sendable {
        /// An event of the subscribed stream (or of `$all`).
        case event(ReadEvent)
        /// Everything written before the subscription has been delivered; from here on events
        /// arrive as they are written. Sent again after every ``fellBehind(_:)``. ``CaughtUp``
        /// carries the server's time and the resume position.
        case caughtUp(CaughtUp)
        /// Writes have outpaced the consumer, so the subscription is reading history again;
        /// ``caughtUp(_:)`` follows once it is current. Sent by KurrentDB 26.2.2 and later; an older
        /// server returns to catch-up silently. ``FellBehind`` carries the server's time and the resume position.
        case fellBehind(FellBehind)
        /// A `$all` subscription with a filter has scanned everything up to this position
        /// without a match. Store it as the resume point, so a long stretch without matching
        /// events does not have to be scanned again after a restart. ``Checkpoint`` carries the
        /// position scanned up to and the server's time.
        case checkpoint(Checkpoint)
    }

    /// The subscription has delivered everything written so far and is live.
    public struct CaughtUp: Sendable, Equatable, Hashable, CustomStringConvertible {
        /// The server's clock when it caught up. `nil` only from a server that sends the
        /// notification without fields: KurrentDB 24.10.4 or earlier, or 25.0.0.
        public let timestamp: Date?
        /// Filled only for stream targets (the decoder checks `Target`).
        let streamRevision: UInt64?
        /// Filled only for `$all` (the decoder checks `Target`).
        let allPosition: StreamPosition?

        /// The decoder's initialiser: it fills only the target's own field.
        package init(timestamp: Date?, streamRevision: UInt64?, allPosition: StreamPosition?) {
            self.timestamp = timestamp
            self.streamRevision = streamRevision
            self.allPosition = allPosition
        }

        /// The timestamp and the target's own resume point.
        public var description: String {
            let timestamp = timestamp.map { String(describing: $0) } ?? "nil"
            if Target.self is any SpecifiedStreamTarget.Type {
                return "CaughtUp(timestamp: \(timestamp), revision: \(streamRevision.map { "\($0)" } ?? "nil"))"
            }
            return "CaughtUp(timestamp: \(timestamp), position: \(allPosition.map { "\($0.commit)/\($0.prepare)" } ?? "nil"))"
        }
    }

    /// The subscription is reading history again because writes outpaced the consumer. Sent by
    /// KurrentDB 26.2.2 and later to a client declaring compatibility level 2.
    public struct FellBehind: Sendable, Equatable, Hashable, CustomStringConvertible {
        /// The server's clock when the subscription fell behind.
        public let timestamp: Date?
        /// Filled only for stream targets (the decoder checks `Target`).
        let streamRevision: UInt64?
        /// Filled only for `$all` (the decoder checks `Target`).
        let allPosition: StreamPosition?

        /// The decoder's initialiser: it fills only the target's own field.
        package init(timestamp: Date?, streamRevision: UInt64?, allPosition: StreamPosition?) {
            self.timestamp = timestamp
            self.streamRevision = streamRevision
            self.allPosition = allPosition
        }

        /// The timestamp and the target's own resume point.
        public var description: String {
            let timestamp = timestamp.map { String(describing: $0) } ?? "nil"
            if Target.self is any SpecifiedStreamTarget.Type {
                return "FellBehind(timestamp: \(timestamp), revision: \(streamRevision.map { "\($0)" } ?? "nil"))"
            }
            return "FellBehind(timestamp: \(timestamp), position: \(allPosition.map { "\($0.commit)/\($0.prepare)" } ?? "nil"))"
        }
    }

    /// A filtered `$all` subscription scanned up to here without a match. Never sent to a
    /// single-stream subscription; `case .checkpoint: break` is the right handler there.
    public struct Checkpoint: Sendable, Equatable, Hashable {
        /// The position scanned up to: store it as the resume point.
        public let position: StreamPosition
        /// The server's clock when it reported the checkpoint.
        public let timestamp: Date?

        /// Creates a checkpoint, for a fake subscription in a test.
        public init(position: StreamPosition, timestamp: Date? = nil) {
            self.position = position
            self.timestamp = timestamp
        }
    }
}

extension Streams.Subscription.CaughtUp where Target: SpecifiedStreamTarget {
    /// The number of the last event delivered, or the requested start point: resume **after** it. `nil` until an
    /// event is delivered when the subscription started at `.start`, or at `.end` of a stream with no events.
    public var revision: UInt64? { streamRevision }

    /// Creates the notification, for a fake subscription in a test.
    public init(timestamp: Date? = nil, revision: UInt64? = nil) {
        self.init(timestamp: timestamp, streamRevision: revision, allPosition: nil)
    }
}

extension Streams.Subscription.CaughtUp where Target == AllStreamsTarget {
    /// The position of the last event or checkpoint delivered, or the requested start point (`.end` gives the log's
    /// last indexed position at once): resume **after** it. `nil` until an event or checkpoint is delivered when
    /// started at `.start` (a filtered subscription always has one by the time it catches up).
    public var position: StreamPosition? { allPosition }

    /// Creates the notification, for a fake subscription in a test.
    public init(timestamp: Date? = nil, position: StreamPosition? = nil) {
        self.init(timestamp: timestamp, streamRevision: nil, allPosition: position)
    }
}

extension Streams.Subscription.FellBehind where Target: SpecifiedStreamTarget {
    /// The number of the last event delivered, or the requested start point: resume **after** it. `nil` until an
    /// event is delivered when the subscription started at `.start`, or at `.end` of a stream with no events.
    public var revision: UInt64? { streamRevision }

    /// Creates the notification, for a fake subscription in a test.
    public init(timestamp: Date? = nil, revision: UInt64? = nil) {
        self.init(timestamp: timestamp, streamRevision: revision, allPosition: nil)
    }
}

extension Streams.Subscription.FellBehind where Target == AllStreamsTarget {
    /// The position of the last event or checkpoint delivered, or the requested start point: resume **after** it.
    /// `nil` until an event or checkpoint is delivered when started at `.start`.
    public var position: StreamPosition? { allPosition }

    /// Creates the notification, for a fake subscription in a test.
    public init(timestamp: Date? = nil, position: StreamPosition? = nil) {
        self.init(timestamp: timestamp, streamRevision: nil, allPosition: position)
    }
}
