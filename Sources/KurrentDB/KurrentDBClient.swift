//
//  KurrentDBClient.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/1/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2
import NIO
import NIOSSL

/// The primary entry point for interacting with a KurrentDB cluster.
///
/// `KurrentDBClient` provides a high-level, type-safe interface for performing all operations
/// against KurrentDB, including stream operations, projections, persistent subscriptions, user
/// management, and cluster operations. The client is implemented as an actor to ensure thread-safe
/// access in concurrent environments.
///
/// ## Connection Management
///
/// The client manages connections to one or more KurrentDB nodes through a `NodeSelector`, which
/// handles node discovery, leader/follower selection, and automatic reconnection. Connection
/// settings are configured via `ClientSettings`, which supports:
/// - Single-node connections
/// - DNS-based cluster discovery
/// - Gossip-based cluster discovery with seed nodes
///
/// ## Thread Safety
///
/// As an actor, `KurrentDBClient` ensures all operations are executed serially, preventing
/// concurrent access issues. All public methods are async and properly isolated.
///
/// ## Usage Example
///
/// ```swift
/// // Create client with localhost settings
/// let settings = ClientSettings.localhost()
///     .authenticated(.credentials(username: "admin", password: "changeit"))
/// let client = KurrentDBClient(settings: settings)
///
/// // Append events to a stream
/// try await client.appendToStream("orders", events: [
///     EventData(eventType: "OrderCreated", model: ["orderId": "123"])
/// ])
///
/// // Read events from a stream
/// let events = try await client.readStream(.init(name: "orders"))
/// for try await response in events {
///     if case .event(let readEvent) = response {
///         print(readEvent)
///     }
/// }
/// ```
///
/// - SeeAlso: `ClientSettings`, `NodeSelector`, `Streams`, `Projections`
public actor KurrentDBClient: Sendable, Buildable {
    /// The default call options applied to all RPC operations unless overridden.
    ///
    /// These options control behavior such as request timeouts, metadata headers,
    /// and compression settings for all gRPC calls made by this client.
    public private(set) var defaultCallOptions: CallOptions

    /// The connection settings defining cluster endpoints, credentials, and TLS configuration.
    public private(set) var settings: ClientSettings

    /// The event loop group used for asynchronous I/O operations.
    ///
    /// This event loop group manages network connections and handles concurrent requests.
    /// It can either be created internally or shared with the application.
    package let eventLoopGroup: EventLoopGroup

    /// The node selector responsible for cluster discovery and endpoint selection.
    ///
    /// Handles routing requests to appropriate cluster nodes based on node preference
    /// (leader, follower, or random) and maintains connection health.
    package var selector: NodeSelector

    /// Creates a new client instance with an internally managed event loop group.
    ///
    /// This initializer creates a dedicated `MultiThreadedEventLoopGroup` for the client's
    /// use. The event loop group will be owned by the client and should not be shared with
    /// other components. For applications already managing an event loop group, use
    /// `init(settings:eventLoopGroup:defaultCallOptions:)` instead.
    ///
    /// - Parameters:
    ///   - settings: Connection settings including cluster endpoints, authentication credentials,
    ///     and TLS configuration. Use `ClientSettings.localhost()` for local development or
    ///     configure cluster endpoints for production environments.
    ///   - numberOfThreads: The number of threads to allocate for the event loop group.
    ///     Increase this value for applications with high concurrency requirements. Defaults to 1.
    ///   - defaultCallOptions: Default gRPC call options applied to all requests. These can include
    ///     timeouts, custom metadata, or compression settings. Defaults to `.defaults`.
    ///
    /// - Note: The event loop group will continue running for the lifetime of this client instance.
    ///   Ensure proper cleanup by allowing the client to be deallocated when no longer needed.
    ///
    /// - SeeAlso: `ClientSettings`, `CallOptions`
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        selector = .init(settings: settings)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }

    /// Creates a new client instance using an externally managed event loop group.
    ///
    /// Use this initializer when your application already manages an event loop group that should
    /// be shared across multiple clients or services. This is the preferred approach for applications
    /// using SwiftNIO or other async frameworks, as it allows for better resource management and
    /// coordination of concurrent operations.
    ///
    /// - Parameters:
    ///   - settings: Connection settings including cluster endpoints, authentication credentials,
    ///     and TLS configuration. Use `ClientSettings.localhost()` for local development or
    ///     configure cluster endpoints for production environments.
    ///   - eventLoopGroup: An existing event loop group to use for network operations. The caller
    ///     retains ownership and is responsible for the lifecycle of this event loop group.
    ///   - defaultCallOptions: Default gRPC call options applied to all requests. These can include
    ///     timeouts, custom metadata, or compression settings. Defaults to `.defaults`.
    ///
    /// - Important: The caller is responsible for keeping the event loop group alive for the entire
    ///   lifetime of this client. Shutting down the event loop group while the client is active will
    ///   cause all pending operations to fail.
    ///
    /// - SeeAlso: `ClientSettings`, `CallOptions`, `EventLoopGroup`
    public init(settings: ClientSettings, eventLoopGroup: EventLoopGroup, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        selector = .init(settings: settings)
        self.eventLoopGroup = eventLoopGroup
    }
}

/// Provides access to core service instances.
extension KurrentDBClient {
    /// Accesses the cluster monitoring service for health checks and status information.
    ///
    /// The monitoring service provides real-time information about the KurrentDB cluster,
    /// including node health, cluster state, and operational metrics. This is useful for
    /// building health dashboards, implementing service health checks, or monitoring
    /// cluster performance.
    ///
    /// The returned `Monitoring` instance is pre-configured with:
    /// - The client's `NodeSelector` for automatic endpoint selection
    /// - The client's `defaultCallOptions` for consistent request behavior
    /// - The shared `EventLoopGroup` for efficient I/O operations
    ///
    /// ## Common Use Cases
    ///
    /// - Health check endpoints in web services
    /// - Monitoring dashboards and alerting systems
    /// - Cluster state verification before critical operations
    /// - Performance metrics collection
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Check cluster health
    /// let health = try await client.monitoring.health()
    /// print("Cluster is healthy: \(health.isHealthy)")
    /// ```
    ///
    /// - Returns: A configured `Monitoring` service instance.
    ///
    /// - Note: All monitoring operations are read-only and safe to call frequently.
    ///   However, excessive polling may impact cluster performance.
    ///
    /// - SeeAlso: `Monitoring`
    public var monitoring: Monitoring {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Creates an operations interface for a specific target type.
    ///
    /// Returns a type-safe `Operations` instance scoped to the given target.
    /// The target determines which operations are available at compile time.
    ///
    /// ## Available Targets
    ///
    /// | Target | Factory | Available Operations |
    /// |--------|---------|---------------------|
    /// | `ScavengeOperations` | `.scavenge` | `startScavenge(threadCount:startFromChunk:)` |
    /// | `ActiveScavenge` | `.activeScavenge(scavengeId:)` | `stopScavenge()` |
    /// | `SystemOperations` | `.system` | `shutdown()`, `mergeIndexes()`, `restartPersistentSubscriptions()` |
    /// | `NodeOperations` | `.node` | `resignNode()`, `setNodePriority(priority:)` |
    ///
    /// ## Example
    ///
    /// ```swift
    /// // System operations
    /// try await client.operations(of: .system).shutdown()
    /// try await client.operations(of: .system).mergeIndexes()
    /// try await client.operations(of: .system).restartPersistentSubscriptions()
    ///
    /// // Scavenge operations
    /// let response = try await client.operations(of: .scavenge)
    ///     .startScavenge(threadCount: 2, startFromChunk: 0)
    /// try await client.operations(of: .activeScavenge(scavengeId: response.scavengeId))
    ///     .stopScavenge()
    ///
    /// // Node operations
    /// try await client.operations(of: .node).resignNode()
    /// try await client.operations(of: .node).setNodePriority(priority: 10)
    /// ```
    ///
    /// - Parameter target: The operations target specifying the scope and available operations.
    ///
    /// - Returns: A configured `Operations` instance with methods constrained by the target type.
    ///
    /// - SeeAlso: `OperationsTarget`, `ScavengeOperations`, `ActiveScavenge`, `SystemOperations`, `NodeOperations`
    public func operations<Target: OperationsTarget>(of target: Target) -> Operations<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}
