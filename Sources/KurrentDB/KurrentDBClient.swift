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
/// for try await event in client.allStreams.read() {
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

    /// The event-loop group this client's connections run on. Injected, never owned: the client
    /// does not shut it down.
    package let eventLoopGroup: any EventLoopGroup

    /// Node selector that performs cluster discovery and routes requests to the best node.
    ///
    /// The client has no `deinit` that closes connections: facades (`Streams`, `Projections`, ...)
    /// and returned subscriptions may outlive this client and keep the connection provider alive
    /// through the selector; the provider closes its own connections when its last reference goes.
    package let selector: NodeSelector

    /// Creates a client.
    ///
    /// - Parameters:
    ///   - settings: Connection and authentication configuration. Use `.localhost()` for local development.
    ///   - eventLoopGroup: The event-loop group every connection of this client runs on. Defaults to
    ///     NIO's process-wide `.singletonMultiThreadedEventLoopGroup`, which grpc-swift uses anyway.
    ///     Pass a group you already run (a Hummingbird server's, for example) so KurrentDB I/O shares
    ///     its loops, or a private `MultiThreadedEventLoopGroup(numberOfThreads:)` to keep it apart.
    ///     The connections use grpc-swift's NIO Posix transport, which needs a
    ///     `MultiThreadedEventLoopGroup` or one of its event loops; a NIO Transport Services group
    ///     does not work. The client never shuts the group down: you own its lifetime, and shut it
    ///     down (if it is not the singleton) only after ``shutdown()``.
    ///   - defaultCallOptions: gRPC call options applied to all outgoing requests. Defaults to `.defaults`.
    public init(
        settings: ClientSettings,
        eventLoopGroup: any EventLoopGroup = .singletonMultiThreadedEventLoopGroup,
        defaultCallOptions: CallOptions = .defaults
    ) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.eventLoopGroup = eventLoopGroup
        self.selector = .init(settings: settings, eventLoopGroup: eventLoopGroup)
    }
}

extension KurrentDBClient {
    /// Closes every connection this client opened and rejects further calls.
    ///
    /// After shutdown, every operation made through this client — including through
    /// facades obtained from it earlier — throws `KurrentError.connectionClosed`, and
    /// in-progress reads and active subscriptions end.
    ///
    /// Shutdown is *initiated*, not awaited: connections are cancelled, but may still be
    /// closing when this method returns. The event-loop group passed to
    /// ``init(settings:eventLoopGroup:defaultCallOptions:)`` is left running; its owner shuts it
    /// down.
    ///
    /// This closes this client; it never stops the server. Code written against `KurrentDB_V1`,
    /// whose `client.shutdown()` shut the server down, uses
    /// `try await client.operations(of: .system).shutdown()` for that.
    ///
    /// Safe to call multiple times; calls after the first have no effect.
    public func shutdown() {
        selector.connections.shutdown()
    }
}
