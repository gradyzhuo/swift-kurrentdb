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
public struct KurrentDBClient: Sendable, Buildable {
    
    /// Default gRPC call options applied to all client operations.
    ///
    /// These options control the behavior of gRPC calls made by the client, including timeouts,
    /// custom metadata, compression settings, and other request-level configurations. All operations
    /// performed through this client instance will use these options unless explicitly overridden
    /// on a per-call basis.
    ///
    /// ## Common Use Cases
    ///
    /// - Setting request timeouts to prevent indefinite blocking
    /// - Adding custom metadata headers for authentication or tracing
    /// - Configuring compression for network efficiency
    /// - Enabling or disabling specific gRPC features
    ///
    /// ## Modifying Call Options
    ///
    /// While `defaultCallOptions` can be updated, it's recommended to configure them during
    /// client initialization for consistency:
    ///
    /// ```swift
    /// var callOptions = CallOptions.defaults
    /// callOptions.timeLimit = .timeout(.seconds(30))
    ///
    /// let client = KurrentDBClient(
    ///     settings: settings,
    ///     defaultCallOptions: callOptions
    /// )
    /// ```
    ///
    /// - Note: Changes to this property affect all subsequent operations but do not impact
    ///   requests that are already in flight.
    ///
    /// - SeeAlso: `CallOptions` from GRPCCore for available configuration options
    public let defaultCallOptions: CallOptions

    
    /// The configuration settings that define how the client connects to and interacts with the KurrentDB cluster.
    ///
    /// This property contains all connection parameters including cluster endpoints, authentication
    /// credentials, TLS configuration, and discovery mechanisms. The settings are established during
    /// client initialization and remain immutable throughout the client's lifetime to ensure consistent
    /// behavior.
    ///
    /// ## Key Configuration Areas
    ///
    /// - **Connection Endpoints**: Single-node address or cluster discovery configuration
    /// - **Authentication**: Credentials or token-based authentication settings
    /// - **TLS/SSL**: Certificate validation and secure connection options
    /// - **Node Preferences**: Whether to prefer leaders, followers, or random nodes for operations
    /// - **Timeouts and Retry Policies**: Request-level behavior configuration
    ///
    /// ## Access Pattern
    ///
    /// While this property is publicly readable, it is privately settable to prevent runtime
    /// configuration changes that could lead to inconsistent client behavior. To modify settings,
    /// create a new client instance with the desired configuration.
    ///
    /// ## Usage Example
    ///
    /// ```swift
    /// // Access current settings
    /// let currentEndpoints = client.settings.endpoints
    /// let authMode = client.settings.authentication
    ///
    /// // To change settings, create a new client
    /// let newSettings = ClientSettings.cluster(["node1:2113", "node2:2113"])
    ///     .authenticated(.credentials(username: "admin", password: "changeit"))
    /// let newClient = KurrentDBClient(settings: newSettings)
    /// ```
    ///
    /// - SeeAlso: `ClientSettings` for available configuration options and factory methods
    public let settings: ClientSettings

    /// The event loop group used for asynchronous I/O operations.
    ///
    /// This event loop group manages network connections and handles concurrent requests.
    /// It can either be created internally or shared with the application.
    package let eventLoopGroup: EventLoopGroup

    /// The node selector responsible for cluster discovery and endpoint selection.
    ///
    /// Handles routing requests to appropriate cluster nodes based on node preference
    /// (leader, follower, or random) and maintains connection health.
    package let selector: NodeSelector

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
        self.selector = .init(settings: settings)
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
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
    private init(settings: ClientSettings, eventLoopGroup: EventLoopGroup, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.selector = .init(settings: settings)
        self.eventLoopGroup = eventLoopGroup
    }
}

extension KurrentDBClient {
    /// Shuts down the client's event loop group, releasing all network resources.
    ///
    /// Call this when you are done with the client and it was created with the default
    /// initializer (i.e., not sharing an external `EventLoopGroup`). Safe to call multiple times.
    public func shutdown() throws {
        try eventLoopGroup.syncShutdownGracefully()
    }
}
