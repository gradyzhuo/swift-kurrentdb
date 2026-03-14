//
//  KurrentDBClientProtocol.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/25.
//

/// A protocol mirroring all public factory methods on ``KurrentDBClient``.
///
/// Conform to this protocol in test doubles to enable dependency injection without depending
/// on a live client. ``KurrentDBClient`` itself conforms, so production code can accept
/// `any KurrentDBClientProtocol` and tests can substitute a mock.
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

    /// Creates a streams interface for the given target (`.specified(_:)`, `.all`, `.multiple`).
    func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target>

    /// Creates a streams interface for a specific stream by name.
    func streams(specified name: String) -> Streams<SpecifiedStream>

    /// The `$all` stream for global event log operations (read, subscribe).
    var allStreams: Streams<AllStreamsTarget> { get }

    /// Batch operations across multiple streams (requires server 25.1+).
    var multiStreams: Streams<MultiStreamsTarget> { get }

    // MARK: - Persistent Subscriptions

    /// Cluster-wide persistent subscription operations (list, restart subsystem).
    var allPersistentSubscriptions: PersistentSubscriptions<AllPersistentSubscriptionTarget> { get }

    /// Creates a persistent subscriptions interface for a specific target type.
    func persistentSubscriptions<Target: PersistentSubscriptionTarget>(of target: Target) -> PersistentSubscriptions<Target>

    /// Creates a persistent subscriptions interface for a specific stream and consumer group.
    func persistentSubscriptions(stream: String, group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>

    /// Persistent subscriptions filtered by consumer group name across all streams.
    func persistentSubscriptions(filterGroup groupName: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget>

    /// Persistent subscriptions filtered by stream name.
    func persistentSubscriptions(filterStream stream: String) -> PersistentSubscriptions<FilterStreamPersistentSubscriptionTarget>

    // MARK: - Users

    /// User management service for cluster-wide operations (create, list).
    var users: Users<AllUsersTarget> { get }

    /// User interface scoped to a specific user by login name.
    func user(_ loginName: String) -> Users<SpecifiedUserTarget>

    // MARK: - Server Operations

    /// Server operations interface for the given target (`.system`, `.scavenge`, `.node`).
    func operations<Target: OperationsTarget>(of target: Target) -> Operations<Target>

    // MARK: - Monitoring

    /// Cluster monitoring service for health checks and server statistics.
    var monitoring: Monitoring { get }
}

extension KurrentDBClient: KurrentDBClientProtocol {}
