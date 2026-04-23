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

/// Primary entry point for interacting with a KurrentDB cluster.
///
/// Access subsystems through factory methods and computed properties, then perform async operations
/// on the returned value.
///
/// ```swift
/// let client = KurrentDBClient(
///     settings: .localhost()
///         .authenticated(.credentials(username: "admin", password: "changeit"))
/// )
///
/// // Append to a specific stream
/// try await client.streams(specified: "orders").append(events: events)
///
/// // Read from the global $all stream
/// for try await event in try await client.allStreams.read() {
///     print(event)
/// }
/// ```
///
/// - SeeAlso: ``ClientSettings``, ``KurrentDBClientProtocol``
public final class KurrentDBClient: Sendable, Buildable {

    /// Default gRPC call options applied to every request made through this client.
    public let defaultCallOptions: CallOptions

    /// Connection and authentication settings used by this client.
    public let settings: ClientSettings

    /// Event loop group that drives all asynchronous network I/O for this client.
    package let eventLoopGroup: EventLoopGroup

    /// Node selector that performs cluster discovery and routes requests to the best node.
    package let selector: NodeSelector

    private let isShutdown = Mutex<Bool>(false)

    /// Creates a client that manages its own event loop group.
    ///
    /// - Parameters:
    ///   - settings: Connection and authentication configuration. Use `.localhost()` for local development.
    ///   - numberOfThreads: Number of threads to allocate for the internal event loop group. Defaults to `1`.
    ///   - defaultCallOptions: gRPC call options applied to all outgoing requests. Defaults to `.defaults`.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.selector = .init(settings: settings)
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }

    /// Creates a client sharing an externally owned event loop group.
    ///
    /// - Parameters:
    ///   - settings: Connection and authentication configuration.
    ///   - eventLoopGroup: An existing event loop group whose lifetime the caller manages.
    ///   - defaultCallOptions: gRPC call options applied to all outgoing requests. Defaults to `.defaults`.
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
    /// Shuts down the internal event loop group and releases all network resources.
    ///
    /// Safe to call multiple times. Has no effect if the client was already shut down or deinitialized.
    ///
    /// - Throws: Any error raised by the underlying NIO `syncShutdownGracefully()`.
    public func shutdown() throws {
        isShutdown.withLock { $0 = true }
        try eventLoopGroup.syncShutdownGracefully()
    }
}
