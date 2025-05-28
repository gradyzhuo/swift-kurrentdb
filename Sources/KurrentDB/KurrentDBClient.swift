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

/// A client encapsulating gRPC use cases for EventStoreDB.
///
/// `KurrentDBClient` provides a high-level interface to interact with EventStoreDB, offering access to
/// streams, persistent subscriptions, projections, users, monitoring, and operations. It conforms to
/// `Sendable` and `Buildable` for safe concurrency and flexible construction.
///
/// - Note: This client relies on **gRPC** and requires a valid `ClientSettings` configuration.
///
/// ### Topics
/// #### Stream Operations
/// - ``setStreamMetadata(_:metadata:expectedRevision:)``
/// - ``getStreamMetadata(_:)``
/// - ``appendStream(_:events:configure:)``
/// - ``readAllStreams(startFrom:configure:)``
/// - ``readStream(_:startFrom:configure:)``
/// - ``subscribeAllStreams(startFrom:configure:)``
/// - ``subscribeStream(_:startFrom:configure:)``
/// - ``deleteStream(_:configure:)``
/// - ``tombstoneStream(_:configure:)``
/// - ``copyStream(_:toNewStream:)``
///
/// #### Persistent Subscription Operations
/// - ``createPersistentSubscription(to:groupName:startFrom:configure:)``
/// - ``createPersistentSubscriptionToAllStream(groupName:startFrom:configure:)``
/// - ``deletePersistentSubscription(to:groupName:)``
/// - ``deletePersistentSubscriptionToAllStream(groupName:)``
/// - ``listPersistentSubscriptions(to:)``
/// - ``listPersistentSubscriptionsToAllStream()``
/// - ``listAllPersistentSubscription()``
///
/// #### Projection Operations
/// - ``createContinuousProjection(name:query:configure:)``
/// - ``updateProjection(name:query:configure:)``
/// - ``disableProjection(name:)``
/// - ``abortProjection(name:)``
/// - ``deleteProjection(name:configure:)``
/// - ``resetProjection(name:)``
/// - ``getProjectionResult(name:configure:)``
/// - ``getProjectionState(name:configure:)``
/// - ``getProjectionDetail(name:)``
/// - ``restartProjectionSubsystem()``
///
/// #### User Management
/// - ``users``
///
/// #### Monitoring
/// - ``monitoring``
///
/// #### Server Operations
/// - ``operations``
/// - ``startScavenge(threadCount:startFromChunk:)``
/// - ``stopScavenge(scavengeId:)``
public actor KurrentDBClient: Sendable, Buildable {
    /// The default gRPC call options for all operations.
    ///
    /// These options are applied to all gRPC calls unless overridden by specific method configurations.
    /// - Note: This property is read-only and set during initialization.
    public private(set) var defaultCallOptions: CallOptions
    
    /// The client settings for establishing a gRPC connection.
    ///
    /// Encapsulates configuration details such as server endpoints, authentication, and SSL settings.
    /// - Note: This property is read-only and set during initialization.
    public private(set) var settings: ClientSettings
    
    package let eventLoopGroup: EventLoopGroup
    
    package var selector: NodeSelector

    /// Initializes a `KurrentDBClient` with settings and thread configuration.
    ///
    /// - Parameters:
    ///   - settings: The client settings encapsulating configuration details, such as server endpoints and credentials.
    ///   - numberOfThreads: The number of threads for the `EventLoopGroup`, defaulting to 1.
    ///   - defaultCallOptions: The default call options for all gRPC calls, defaulting to `.defaults`.
    /// - Note: The client is an `actor`, so all interactions must use `await` in asynchronous contexts.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.selector = .init(settings: settings)
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }
    
    public init(settings: ClientSettings, eventLoopGroup: EventLoopGroup, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.selector = .init(settings: settings)
        self.eventLoopGroup = eventLoopGroup
    }
    
    
}

/// Provides access to core service instances.
extension KurrentDBClient {
    package func streams<Target: StreamTarget>(of target: Target) -> Streams<Target> {
        return .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
    
    package var persistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        return .init(target: .all, selector: selector, callOptions: defaultCallOptions)
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
