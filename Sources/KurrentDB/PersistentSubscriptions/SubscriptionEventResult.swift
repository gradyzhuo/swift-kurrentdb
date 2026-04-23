//
//  SubscriptionEventResult.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/4/23.
//


/// A type that carries the stream position metadata required by a generic ``PersistentSubscriptions/Subscription``.
///
/// Conform your custom event-result type to this protocol when you specialise
/// `Subscription<EventResult>` with a type other than the built-in
/// `PersistentSubscription.EventResult`.  The subscription uses `revision` and
/// `position` to track the last successfully received event so that callers can
/// resume after a drop.
public protocol SubscriptionEventResult: Sendable {
    /// Stream revision of the event, or `nil` if the event has no revision (e.g. system events).
    var revision: UInt64? { get }
    /// Global log position of the event in the `$all` stream, or `nil` if unavailable.
    var position: StreamPosition? { get }
}
