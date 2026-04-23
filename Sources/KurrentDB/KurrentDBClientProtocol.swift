//
//  KurrentDBClientProtocol.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/25.
//

/// Abstraction over ``KurrentDBClient`` that enables dependency injection and test doubles.
///
/// Production code that accepts `any KurrentDBClientProtocol` can be tested by substituting a
/// mock without depending on a live server. ``KurrentDBClient`` conforms to this protocol.
///
/// ```swift
/// struct OrderService {
///     let db: any KurrentDBClientProtocol
///
///     func placeOrder(_ order: Order) async throws {
///         let events = [EventData(eventType: "OrderPlaced", model: order)]
///         try await db.streams(specified: "orders").append(events: events)
///     }
/// }
/// ```
///
/// - SeeAlso: ``KurrentDBClient``
public protocol KurrentDBClientProtocol: Sendable {

    // MARK: - Streams

    /// Returns a streams interface scoped to the given target.
    ///
    /// - Parameter target: The stream target (`.specified(_:)`, `.all`, or `.multiple`).
    /// - Returns: A ``Streams`` instance bound to `Target`.
    func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target>

    /// Returns a streams interface scoped to a single named stream.
    ///
    /// - Parameter name: The stream name.
    /// - Returns: A ``Streams`` instance scoped to the specified stream.
    func streams(specified name: String) -> Streams<SpecifiedStream>

    /// Streams interface for the global `$all` stream.
    var allStreams: Streams<AllStreamsTarget> { get }

    /// Streams interface for batch operations across multiple streams (requires server 25.1+).
    var multiStreams: Streams<MultiStreamsTarget> { get }

    // MARK: - Persistent Subscriptions

    /// Persistent subscriptions interface for cluster-wide operations such as listing all subscriptions.
    var allPersistentSubscriptions: PersistentSubscriptions<AllPersistentSubscriptionTarget> { get }

    /// Returns a persistent subscriptions interface for the given target.
    ///
    /// - Parameter target: The persistent subscription target.
    /// - Returns: A ``PersistentSubscriptions`` instance bound to `Target`.
    func persistentSubscriptions<Target: PersistentSubscriptionTarget>(of target: Target) -> PersistentSubscriptions<Target>

    /// Returns a persistent subscriptions interface scoped to a specific stream and consumer group.
    ///
    /// - Parameters:
    ///   - stream: The stream name the subscription reads from.
    ///   - group: The consumer group name.
    /// - Returns: A ``PersistentSubscriptions`` instance for the specified stream and group.
    func persistentSubscriptions(stream: String, group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>

    /// Returns a persistent subscriptions interface for the `$all` stream scoped to a specific consumer group.
    ///
    /// - Parameter groupName: The consumer group name to filter by.
    /// - Returns: A ``PersistentSubscriptions`` instance targeting the `$all` stream for the given group.
    func persistentSubscriptions(filterGroup groupName: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget>

    /// Returns a persistent subscriptions interface filtered to subscriptions on a specific stream.
    ///
    /// - Parameter stream: The stream name to filter by.
    /// - Returns: A ``PersistentSubscriptions`` instance scoped to the given stream.
    func persistentSubscriptions(filterStream stream: String) -> PersistentSubscriptions<FilterStreamPersistentSubscriptionTarget>

    // MARK: - Users

    /// User management interface for cluster-wide operations such as creating and listing users.
    var users: Users<AllUsersTarget> { get }

    /// Returns a user management interface scoped to a single user.
    ///
    /// - Parameter loginName: The login name of the user.
    /// - Returns: A ``Users`` instance scoped to the specified user.
    func user(_ loginName: String) -> Users<SpecifiedUserTarget>

    // MARK: - Server Operations

    /// Returns a server operations interface for the given target.
    ///
    /// - Parameter target: The operations target (e.g., scavenge, node operations).
    /// - Returns: An ``Operations`` instance bound to `Target`.
    func operations<Target: OperationsTarget>(of target: Target) -> Operations<Target>

    // MARK: - Monitoring

    /// Monitoring interface for cluster health checks and server statistics.
    var monitoring: Monitoring { get }
}

extension KurrentDBClient: KurrentDBClientProtocol {}
