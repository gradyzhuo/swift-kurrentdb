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
import Synchronization

/// The primary entry point for interacting with a KurrentDB cluster.
///
/// `KurrentDBClient` provides a high-level, type-safe interface for all KurrentDB operations.
/// Access different subsystems through factory methods and properties:
///
/// | Subsystem | Access |
/// |-----------|--------|
/// | Streams | `streams(specified:)`, `allStreams`, `multiStreams` |
/// | Projections | `projections(name:)`, `projections(system:)` |
/// | Persistent Subscriptions | `persistentSubscriptions(stream:group:)`, `allPersistentSubscriptions` |
/// | Users | `users`, `user(_:)` |
/// | Operations | `operations(of:)` |
/// | Monitoring | `monitoring`, `stats()` |
/// | Gossip | `readCluster()` |
///
/// ## Usage
///
/// ```swift
/// let client = KurrentDBClient(settings: .localhost()
///     .authenticated(.credentials(username: "admin", password: "changeit")))
///
/// // Append events
/// try await client.streams(specified: "orders").append(events: [
///     EventData(eventType: "OrderCreated", model: order)
/// ])
///
/// // Read from $all
/// for try await response in try await client.allStreams.read() {
///     print(response)
/// }
/// ```
///
/// Connections are managed internally via ``NodeSelector``, which handles cluster discovery,
/// leader/follower preference, and automatic reconnection based on ``ClientSettings``.
///
/// - SeeAlso: ``ClientSettings``, ``KurrentDBClientProtocol``, ``Streams``, ``Projections``
public final class KurrentDBClient: Sendable, Buildable {
    
    /// Default gRPC call options applied to all operations performed through this client.
    ///
    /// Controls timeouts, custom metadata, and compression for gRPC calls. Configure during
    /// initialization for consistency:
    ///
    /// ```swift
    /// let client = KurrentDBClient(
    ///     settings: settings,
    ///     defaultCallOptions: callOptions
    /// )
    /// ```
    public let defaultCallOptions: CallOptions

    /// Connection settings including cluster endpoints, authentication, TLS, and discovery configuration.
    ///
    /// Immutable after initialization. To change settings, create a new client instance.
    ///
    /// - SeeAlso: ``ClientSettings``
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

    private let isShutdown = Mutex<Bool>(false)

    /// Creates a new client with an internally managed event loop group.
    ///
    /// - Parameters:
    ///   - settings: Connection and authentication configuration. Use `.localhost()` for local development.
    ///   - numberOfThreads: Thread count for the event loop group. Defaults to `1`.
    ///   - defaultCallOptions: gRPC call options applied to all requests. Defaults to `.defaults`.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.selector = .init(settings: settings)
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }

    /// Creates a new client using an externally managed event loop group.
    ///
    /// Use this when sharing an `EventLoopGroup` across multiple clients or SwiftNIO services.
    ///
    /// - Parameters:
    ///   - settings: Connection and authentication configuration.
    ///   - eventLoopGroup: An existing event loop group. The caller retains ownership and must
    ///     keep it alive for the lifetime of this client.
    ///   - defaultCallOptions: gRPC call options applied to all requests. Defaults to `.defaults`.
    private init(settings: ClientSettings, eventLoopGroup: EventLoopGroup, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.selector = .init(settings: settings)
        self.eventLoopGroup = eventLoopGroup
    }

    deinit {
        let alreadyShutdown = isShutdown.withLock {
            let old = $0
            $0 = true
            return old
        }
        guard !alreadyShutdown else { return }
        eventLoopGroup.shutdownGracefully { error in
            if let error {
                logger.warning("EventLoopGroup shutdown error during deinit: \(error)")
            }
        }
    }
}

extension KurrentDBClient {
    /// Shuts down the client's event loop group, releasing all network resources.
    ///
    /// Call this when you are done with the client and it was created with the default
    /// initializer (i.e., not sharing an external `EventLoopGroup`). Safe to call multiple times.
    public func shutdown() throws {
        isShutdown.withLock { $0 = true }
        try eventLoopGroup.syncShutdownGracefully()
    }
}
