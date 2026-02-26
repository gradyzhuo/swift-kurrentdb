//
//  PersistentSubscriptions.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct PersistentSubscriptions<Target: PersistentSubscriptionTarget>: GRPCConcreteService {
    /// The underlying gRPC service type.
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions

    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = UnderlyingService.Client<HTTP2ClientTransport.Posix>

    /// The settings used for client communication.
    public private(set) var selector: NodeSelector

    /// Options to be used for each gRPC service call.
    public var callOptions: CallOptions

    /// The event loop group for asynchronous execution.
    public let eventLoopGroup: EventLoopGroup

    /// The target stream for the subscription (e.g., specific stream, all streams, or generic).
    public let target: Target

    /// Initializes a `PersistentSubscriptions` instance.
    ///
    /// - Parameters:
    ///   - target: The target stream for the subscription (e.g., `Specified`, `All`, or `AnyTarget`).
    ///   - settings: The settings used for client communication.
    ///   - callOptions: Options for the gRPC call, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group for async operations, defaulting to `.singletonMultiThreadedEventLoopGroup`.
    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
        self.target = target
    }
}

extension PersistentSubscriptions {
    public struct SpecifiedStream {}
    public struct AllStream {}
}

// MARK: - Streams

extension Streams where Target: SpecifiedStreamTarget {
    /// Returns a `PersistentSubscriptions` instance for a specified stream and subscription group.
    ///
    /// - Parameter group: The name of the persistent subscription group.
    /// - Returns: A `PersistentSubscriptions` actor scoped to the given stream identifier and group.
    public func persistentSubscriptions(group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget> {
        let target = SpecifiedPersistentSubscriptionTarget(identifier: target.identifier, group: group)
        return .init(target: target, selector: selector, callOptions: callOptions)
    }
}

extension Streams where Target == AllStreams {
    public func persistentSubscriptions(group: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget> {
        let target = AllStreamPersistentSubscriptionTarget(group: group)
        return .init(target: target, selector: selector, callOptions: callOptions)
    }
}

