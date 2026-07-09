//
//  Monitoring.swift
//  KurrentMonitoring
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

/// gRPC service for retrieving real-time KurrentDB server statistics.
public final class Monitoring: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_Monitoring_Monitoring.Client<HTTP2ClientTransport.Posix>

    internal let selector: NodeSelector
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup

    /// Per-call authentication override, set via ``authenticated(_:)``. When nil, the client-level
    /// authentication from ``ClientSettings`` is used.
    internal let overrideCredentials: Authentication?

    init(selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup, overrideCredentials: Authentication? = nil) {
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
        self.overrideCredentials = overrideCredentials
    }

    /// Returns a copy of this interface that authenticates subsequent calls with the given
    /// credentials, overriding the client-level authentication for those calls only.
    ///
    /// - Parameter credentials: Authentication to use for calls made on the returned instance.
    /// - Returns: A new interface scoped to `credentials`.
    public func authenticated(_ credentials: Authentication) -> Self {
        .init(selector: selector, callOptions: callOptions, eventLoopGroup: eventLoopGroup, overrideCredentials: credentials)
    }
}

extension Monitoring {
    /// Streams server statistics snapshots at the specified refresh interval.
    ///
    /// - Parameters:
    ///   - useMetadata: Include metadata fields in each stats snapshot. Defaults to `false`.
    ///   - refreshTimePeriodInMs: Interval between snapshots in milliseconds. Defaults to `10000` (10 s).
    /// - Returns: An async stream of ``Stats/Response`` snapshots.
    /// - Throws: `KurrentError.accessDenied` if the caller lacks permission to read stats.
    ///   `KurrentError.unavailable` if the server cannot be reached.
    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws(KurrentError) -> Stats.Responses {
        let node = try await selector.select()
        let usecase = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        return try await usecase.perform(node: node, callOptions: callOptions, credentials: overrideCredentials)
    }
}
