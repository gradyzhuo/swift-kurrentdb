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
/// - ``setStreamMetadata(on:metadata:expectedRevision:)``
/// - ``getStreamMetadata(on:)``
/// - ``appendStream(on:events:configure:)``
/// - ``readAllStreams(startFrom:configure:)``
/// - ``readStream(on:startFrom:configure:)``
/// - ``subscribeAllStreams(startFrom:configure:)``
/// - ``subscribeStream(on:startFrom:configure:)``
/// - ``deleteStream(on:configure:)``
/// - ``tombstoneStream(on:configure:)``
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
    public private(set) var defaultCallOptions: CallOptions
    
    /// The client settings for establishing a gRPC connection.
    public private(set) var settings: ClientSettings
    
    /// The event loop group for asynchronous tasks.
    package let group: EventLoopGroup
    
    package var selector: NodeSelector

    /// Initializes a `KurrentDBClient` with settings and thread configuration.
    ///
    /// - Parameters:
    ///   - settings: The client settings encapsulating configuration details.
    ///   - numberOfThreads: The number of threads for the `EventLoopGroup`, defaulting to 1.
    ///   - defaultCallOptions: The default call options for all gRPC calls, defaulting to `.defaults`.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        self.selector = .init(settings: settings)
        group = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }
}

/// Provides access to core service instances.
extension KurrentDBClient {
    /// Creates a `Streams` instance for a specific target.
    ///
    /// - Parameter target: The stream target (e.g., `SpecifiedStream`, `AllStreams`, or `ProjectionStream`).
    /// - Returns: A `Streams` instance configured with the client's settings.
    package func streams<Target: StreamTarget>(of target: Target) -> Streams<Target> {
        return .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The persistent subscriptions service for all streams.
    package var persistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        return .init(target: .all, selector: selector, callOptions: defaultCallOptions)
    }
    
    /// Creates a `Projections` instance for all projections with a specific mode.
    ///
    /// - Parameter mode: The projection mode (e.g., `ContinuousMode` or `AnyMode`).
    /// - Returns: A `Projections` instance configured with the client's settings.
    package func projections<Mode: ProjectionMode>(all mode: Mode) -> Projections<AllProjectionTarget<Mode>> {
        .init(target: .init(mode: mode), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// Creates a `Projections` instance for a named projection.
    ///
    /// - Parameter name: The name of the projection.
    /// - Returns: A `Projections` instance configured with the client's settings.
    package func projections(name: String) -> Projections<String> {
        .init(target: name, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// Creates a `Projections` instance for a system projection.
    ///
    /// - Parameter predefined: The predefined system projection type (e.g., `.byCategory`).
    /// - Returns: A `Projections` instance configured with the client's settings.
    package func projections(system predefined: SystemProjectionTarget.Predefined) -> Projections<SystemProjectionTarget> {
        .init(target: .init(predefined: predefined), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The user management service instance.
    package var users: Users {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The monitoring service instance.
    package var monitoring: Monitoring {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The operations service instance.
    package var operations: Operations {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
}


