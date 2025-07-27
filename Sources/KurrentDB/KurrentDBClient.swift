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

public actor KurrentDBClient: Sendable, Buildable {
    public private(set) var defaultCallOptions: CallOptions
    public private(set) var settings: ClientSettings
    package let eventLoopGroup: EventLoopGroup
    package var selector: NodeSelector

    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        selector = .init(settings: settings)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }

    public init(settings: ClientSettings, eventLoopGroup: EventLoopGroup, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        selector = .init(settings: settings)
        self.eventLoopGroup = eventLoopGroup
    }
}

/// Provides access to core service instances.
extension KurrentDBClient {
    package func streams<Target: StreamTarget>(of target: Target) -> Streams<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    package var persistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions)
    }

    package func projections<Mode: ProjectionMode>(all mode: Mode) -> Projections<AllProjectionTarget<Mode>> {
        .init(target: .init(mode: mode), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    package func projections(name: String) -> Projections<String> {
        .init(target: name, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    package func projections(system predefined: SystemProjectionTarget.Predefined) -> Projections<SystemProjectionTarget> {
        .init(target: .init(predefined: predefined), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    package var users: Users {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    package var monitoring: Monitoring {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    package var operations: Operations {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}
