//
//  Operations.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

/// A gRPC service for managing KurrentDB server operations with type-safe target-based operations.
///
/// `Operations` provides a type-safe interface for server administrative tasks using target-based design.
/// Different operations are available depending on the target type:
///
/// ## Target Types
///
/// - **ScavengeOperations**: Start new scavenge operations
/// - **ActiveScavenge**: Control specific running scavenge operations
/// - **SystemOperations**: System-wide administrative tasks
/// - **NodeOperations**: Cluster node management
///
/// ## Usage
///
/// Starting a scavenge operation:
/// ```swift
/// let scavenges = Operations(target: ScavengeOperations(), selector: selector, ...)
/// let response = try await scavenges.startScavenge(threadCount: 4, startFromChunk: 0)
/// print("Scavenge started with ID: \(response.scavengeId)")
/// ```
///
/// Stopping a specific scavenge:
/// ```swift
/// let active = Operations(target: ActiveScavenge(scavengeId: "abc123"), ...)
/// try await active.stopScavenge()
/// ```
///
/// System operations:
/// ```swift
/// let system = Operations(target: SystemOperations(), ...)
/// try await system.shutdown()
/// ```
///
/// - Note: This service relies on **gRPC** and requires proper authentication.
public actor Operations<Target: OperationsTarget>: GRPCConcreteService {
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Operations_Operations.Client<HTTP2ClientTransport.Posix>

    /// The node selector for routing requests to cluster nodes.
    public private(set) var selector: NodeSelector

    /// Options to be used for each gRPC service call.
    public var callOptions: CallOptions

    /// The event loop group for asynchronous execution.
    public let eventLoopGroup: EventLoopGroup

    /// The target specifying which operations this service can perform.
    private(set) var target: Target

    /// Initializes an `Operations` instance with a specific target.
    ///
    /// - Parameters:
    ///   - target: The operations target specifying the scope of operations.
    ///   - selector: The node selector for cluster node routing.
    ///   - callOptions: Options for the gRPC call, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group for async operations, defaulting to `.singletonMultiThreadedEventLoopGroup`.
    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - Scavenge Creation Operations

extension Operations where Target: ScavengeCreatable {
    /// Starts a scavenge operation to reclaim disk space.
    ///
    /// Scavenging removes deleted events from database chunks, freeing disk space and
    /// improving read performance. The operation runs asynchronously on the server.
    ///
    /// - Parameters:
    ///   - threadCount: The number of parallel threads to use for scavenging. Higher values
    ///     complete faster but increase server load. Typical range: 1-4.
    ///   - startFromChunk: The chunk number to begin scavenging from. Use 0 to start from
    ///     the beginning, or specify a chunk number to resume a previously interrupted scavenge.
    ///
    /// - Returns: A response containing the unique scavenge ID and initial status.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.alreadyExists` if a scavenge is already running.
    ///   `KurrentError.invalidArgument` if parameters are invalid.
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws(KurrentError) -> StartScavenge.Response {
        let node = try await selector.select()
        let usecase = StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        return try await usecase.perform(node: node, callOptions: callOptions)
    }
}

// MARK: - Scavenge Control Operations

extension Operations where Target: ScavengeControllable {
    /// Stops the target scavenge operation gracefully.
    ///
    /// Stops the identified scavenge operation, allowing it to complete its current chunk
    /// before halting. The scavenge position is saved for potential resumption.
    ///
    /// - Returns: A response containing the final status and position of the stopped scavenge.
    ///
    /// - Throws: `KurrentError.notFound` if no scavenge exists with the target ID.
    ///   `KurrentError.accessDenied` if the user lacks administrative permissions.
    public func stopScavenge() async throws(KurrentError) -> StopScavenge.Response {
        let node = try await selector.select()
        let usecase = StopScavenge(scavengeId: target.scavengeId)
        return try await usecase.perform(node: node, callOptions: callOptions)
    }
}

// MARK: - System Operations

extension Operations where Target: SystemControllable {
    /// Merges database indexes to optimize query performance.
    ///
    /// Index merging consolidates index segments, reducing disk I/O and improving
    /// query performance. This operation can be resource-intensive.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the operation cannot be performed.
    public func mergeIndexes() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = MergeIndexes()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Restarts the persistent subscriptions subsystem.
    ///
    /// Stops all persistent subscriptions, clears in-memory state, and reinitializes
    /// the subscription manager. All subscription groups reload from persistent storage.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the subsystem cannot be restarted.
    public func restartPersistentSubscriptions() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = RestartPersistentSubscriptions()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Shuts down the KurrentDB server gracefully.
    ///
    /// Initiates a graceful shutdown, completing in-flight operations and persisting
    /// state before terminating the server process.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///
    /// - Warning: This operation terminates the server. Ensure all clients are prepared
    ///   for disconnection.
    public func shutdown() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = Shutdown()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }
}

// MARK: - Node Operations

extension Operations where Target: NodeControllable {
    /// Resigns the current node from its role in the cluster.
    ///
    /// If the node is a leader, it steps down and triggers a new election. This is useful
    /// for graceful maintenance or cluster rebalancing.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the operation cannot be performed.
    public func resignNode() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = ResignNode()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Sets the priority of the current node for leader election.
    ///
    /// Higher priority nodes are more likely to be elected as leader. Use this to
    /// influence cluster leadership distribution.
    ///
    /// - Parameter priority: The priority value to set. Higher values increase election likelihood.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.invalidArgument` if the priority value is invalid.
    public func setNodePriority(priority: Int32) async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = SetNodePriority(priority: priority)
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }
}
