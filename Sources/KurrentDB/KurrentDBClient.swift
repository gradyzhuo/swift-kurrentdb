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

/// Primary entry point for performing RPCs against a KurrentDB cluster.
/// The client manages the event loop, node selection, and default GRPC call options.
public actor KurrentDBClient: Sendable, Buildable {
    /// Default call options applied to every outbound RPC unless overridden per call.
    public private(set) var defaultCallOptions: CallOptions
    /// Connection settings including endpoints, credentials, and TLS configuration.
    public private(set) var settings: ClientSettings
    package let eventLoopGroup: EventLoopGroup
    package var selector: NodeSelector

    /// Creates a client with an internally managed `MultiThreadedEventLoopGroup`.
    ///
    /// - Parameters:
    ///   - settings: The `ClientSettings` describing how to reach the cluster.
    ///   - numberOfThreads: Event loop thread count; raise this when issuing many concurrent RPCs.
    ///   - defaultCallOptions: Overrides for deadlines, metadata, or compression applied to every call.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        selector = .init(settings: settings)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }

    /// Creates a client that reuses an existing `EventLoopGroup`, useful when embedding in larger apps.
    ///
    /// - Parameters:
    ///   - settings: The `ClientSettings` describing how to reach the cluster.
    ///   - eventLoopGroup: A pre-created event loop group that the caller owns.
    ///   - defaultCallOptions: Overrides for deadlines, metadata, or compression applied to every call.
    public init(settings: ClientSettings, eventLoopGroup: EventLoopGroup, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        selector = .init(settings: settings)
        self.eventLoopGroup = eventLoopGroup
    }
}

/// Provides access to core service instances.
extension KurrentDBClient {
    /// Creates a strongly typed streams facade for the given target kind (specified stream or `$all`).
    ///
    /// - Parameter target: The stream target to operate on.
    /// - Returns: A `Streams` helper scoped to the target.
    package func streams<Target: StreamTarget>(of target: Target) -> Streams<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Lazily constructs a `PersistentSubscriptions` helper that operates cluster-wide.
    package var persistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions)
    }

    /// Creates a projections interface for the given projection mode across every projection.
    ///
    /// - Parameter mode: The desired projection mode (continuous, transient, etc.).
    package func projections<Mode: ProjectionMode>(all mode: Mode) -> Projections<AllProjectionTarget<Mode>> {
        .init(target: .init(mode: mode), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface scoped to a named projection.
    ///
    /// - Parameter name: The projection identifier.
    package func projections(name: String) -> Projections<String> {
        .init(target: name, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface aimed at a predefined system projection.
    ///
    /// - Parameter predefined: The predefined system projection target, such as `$by_category`.
    package func projections(system predefined: SystemProjectionTarget.Predefined) -> Projections<SystemProjectionTarget> {
        .init(target: .init(predefined: predefined), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Provides access to user management RPCs.
    package var users: Users {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Provides access to monitoring RPCs for querying cluster health.
    package var monitoring: Monitoring {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Provides access to server operations such as scavenges.
    package var operations: Operations {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}
