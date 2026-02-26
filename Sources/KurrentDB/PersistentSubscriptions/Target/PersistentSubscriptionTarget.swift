//
//  PersistentSubscriptionTarget.swift
//  KurrentDB
//

/// Represents a target for persistent subscriptions.
///
/// Conform to this protocol to define a subscription scope.
/// Use the static factory methods on the protocol extensions to create targets:
///
/// ```swift
/// // Specific stream
/// let target = SpecifiedPersistentSubscriptionTarget.specified(stream: "orders", group: "workers")
///
/// // All streams
/// let allTarget = AllStreamPersistentSubscriptionTarget.allStreams(group: "workers")
///
/// // Cluster-wide operations
/// let clusterTarget = AllPersistentSubscriptionTarget.all
/// ```
///
/// - Note: This protocol is marked as `Sendable`.
///
/// ### Topics
/// #### Conforming Types
/// - ``SpecifiedPersistentSubscriptionTarget``
/// - ``AllStreamPersistentSubscriptionTarget``
/// - ``FilterStreamPersistentSubscriptionTarget``
/// - ``AllPersistentSubscriptionTarget``
/// - ``AnyPersistentSubscriptionTarget``
public protocol PersistentSubscriptionTarget: Sendable {}
