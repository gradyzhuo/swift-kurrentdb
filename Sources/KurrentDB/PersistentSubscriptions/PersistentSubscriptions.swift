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

/// Service facade for persistent subscription operations scoped to a specific target.
public final class PersistentSubscriptions<Target: PersistentSubscriptionTarget>: GRPCConcreteService {
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions
    package typealias UnderlyingClient = UnderlyingService.Client<HTTP2ClientTransport.Posix>

    internal let selector: NodeSelector
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup

    /// Target that defines which stream or scope this service instance operates on.
    public let target: Target

    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
        self.target = target
    }
}

extension PersistentSubscriptions {
    /// Namespace for persistent subscription operations on a specific named stream.
    public struct SpecifiedStream {}
    /// Namespace for persistent subscription operations on the `$all` stream.
    public struct AllStream {}
}

// MARK: - Streams

extension Streams where Target: SpecifiedStreamTarget {
    /// Returns a `PersistentSubscriptions` scoped to this stream and the given consumer group.
    ///
    /// - Parameter group: Consumer group name.
    /// - Returns: A `PersistentSubscriptions` instance for the specified stream and group.
    public func persistentSubscriptions(group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget> {
        let target = SpecifiedPersistentSubscriptionTarget(identifier: target.identifier, group: group)
        return .init(target: target, selector: selector, callOptions: callOptions)
    }
}

extension Streams where Target == AllStreamsTarget {
    /// Returns a `PersistentSubscriptions` scoped to the `$all` stream and the given consumer group.
    ///
    /// - Parameter group: Consumer group name.
    /// - Returns: A `PersistentSubscriptions` instance for the `$all` stream and group.
    public func persistentSubscriptions(group: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget> {
        let target = AllStreamPersistentSubscriptionTarget(group: group)
        return .init(target: target, selector: selector, callOptions: callOptions)
    }
}

