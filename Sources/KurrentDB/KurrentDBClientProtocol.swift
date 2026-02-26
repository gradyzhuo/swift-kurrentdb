//
//  KurrentDBClientProtocol.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/25.
//

/// A protocol that mirrors all public factory properties and methods on `KurrentDBClient`.
///
/// Conform to this protocol in test doubles or mock objects to enable dependency injection
/// without depending on a live `KurrentDBClient`. `KurrentDBClient` itself conforms to this
/// protocol, so production code can accept `any KurrentDBClientProtocol` and tests can pass
/// a mock implementation.
///
/// ## Example: Dependency Injection
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
///
/// // Production
/// let service = OrderService(db: KurrentDBClient(settings: .localhost()))
///
/// // Tests
/// struct MockClient: KurrentDBClientProtocol { ... }
/// let service = OrderService(db: MockClient())
/// ```
public protocol KurrentDBClientProtocol: Sendable {

    // MARK: - Stream Factories

    /// Creates a type-safe streams interface for the specified target.
    func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target>

    /// Creates a streams interface for a specific stream by name.
    func streams(specified name: String) -> Streams<SpecifiedStream>

    /// Accesses the `$all` stream for global event log operations.
    var allStreams: Streams<AllStreams> { get }

    /// Accesses the multi-streams interface for batch operations across multiple streams.
    var multiStreams: Streams<MultiStreams> { get }

    // MARK: - Persistent Subscription Factories

    /// Returns a persistent subscriptions interface for cluster-wide operations.
    var allPersistentSubscriptions: PersistentSubscriptions<AllPersistentSubscriptionTarget> { get }

    /// Creates a persistent subscriptions interface for a specific target type.
    func persistentSubscriptions<Target: PersistentSubscriptionTarget>(of target: Target) -> PersistentSubscriptions<Target>

    /// Creates a persistent subscriptions interface for a specific stream and group.
    func persistentSubscriptions(stream: String, group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget>

    /// Creates a persistent subscriptions interface filtered by group name across all streams.
    func persistentSubscriptions(filterGroup groupName: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget>

    /// Creates a persistent subscriptions interface filtered by stream name.
    func persistentSubscriptions(filterStream stream: String) -> PersistentSubscriptions<FilterStreamPersistentSubscriptionTarget>

    // MARK: - User Management

    /// Accesses the user management service for operations across all users.
    var users: Users<AllUsersTarget> { get }

    /// Returns a users interface for a specific user by login name.
    func user(_ loginName: String) -> Users<SpecifiedUserTarget>

    // MARK: - Server Operations

    /// Creates an operations interface for a specific target type.
    func operations<Target: OperationsTarget>(of target: Target) -> Operations<Target>

    // MARK: - Monitoring

    /// Accesses the cluster monitoring service for health checks and status information.
    var monitoring: Monitoring { get }
}

extension KurrentDBClient: KurrentDBClientProtocol {}
