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

/// A gRPC service for managing EventStore server operations.
///
/// `Operations` provides methods to perform administrative tasks on an EventStore server, such as
/// scavenging, merging indexes, managing node roles, and shutting down the server.
///
/// ## Usage
///
/// Starting a scavenge operation:
/// ```swift
/// let ops = Operations(settings: clientSettings)
/// let response = try await ops.startScavenge(threadCount: 4, startFromChunk: 0)
/// print("Scavenge started with ID: \(response.scavengeId)")
/// ```
///
/// Shutting down the server:
/// ```swift
/// let ops = Operations(settings: clientSettings)
/// try await ops.shutdown()
/// ```
///
/// - Note: This service relies on **gRPC** and requires a valid `ClientSettings` configuration.
///
/// ### Topics
/// #### Operations
/// - ``startScavenge(threadCount:startFromChunk:)``
/// - ``stopScavenge(scavengeId:)``
/// - ``mergeIndeexes()``
/// - ``resignNode()``
/// - ``restartPersistentSubscriptions()``
/// - ``setNodePriority(priority:)``
/// - ``shutdown()``
public actor Operations: GRPCConcreteService {
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Operations_Operations.Client<HTTP2ClientTransport.Posix>

    /// The settings used for client communication.
    public private(set) var selector: NodeSelector

    /// Options to be used for each gRPC service call.
    public var callOptions: CallOptions

    /// The event loop group for asynchronous execution.
    public let eventLoopGroup: EventLoopGroup

    /// Initializes an `Operations` instance.
    ///
    /// - Parameters:
    ///   - settings: The settings used for client communication.
    ///   - callOptions: Options for the gRPC call, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group for async operations, defaulting to `.singletonMultiThreadedEventLoopGroup`.
    init(selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

/// Provides methods for administrative operations on the EventStore server.
extension Operations {
    /// Starts a scavenge operation to reclaim disk space.
    ///
    /// - Parameters:
    ///   - threadCount: The number of threads to use for the scavenge operation.
    ///   - startFromChunk: The chunk number from which to start scavenging.
    /// - Returns: A `StartScavenge.Response` containing details about the started scavenge operation.
    /// - Throws: An error if the scavenge operation cannot be started.
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws(KurrentError) -> StartScavenge.Response {
        let node = try await selector.select()
        let usecase = StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        return try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Stops an ongoing scavenge operation.
    ///
    /// - Parameter scavengeId: The identifier of the scavenge operation to stop.
    /// - Returns: A `StopScavenge.Response` indicating the result of the stop operation.
    /// - Throws: An error if the scavenge operation cannot be stopped.
    public func stopScavenge(scavengeId: String) async throws(KurrentError) -> StopScavenge.Response {
        let node = try await selector.select()
        let usecase = StopScavenge(scavengeId: scavengeId)
        return try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Merges indexes to optimize database performance.
    ///
    /// - Throws: An error if the merge operation fails.
    public func mergeIndeexes() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = MergeIndexes()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Resigns the current node from its role in a cluster.
    ///
    /// - Throws: An error if the resignation fails.
    public func resignNode() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = ResignNode()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Restarts the persistent subscriptions subsystem.
    ///
    /// - Throws: An error if the restart operation fails.
    public func restartPersistentSubscriptions() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = RestartPersistentSubscriptions()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Sets the priority of the current node in a cluster.
    ///
    /// - Parameter priority: The priority value to set for the node.
    /// - Throws: An error if the priority cannot be set.
    public func setNodePriority(priority: Int32) async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = SetNodePriority(priority: priority)
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Shuts down the EventStore server.
    ///
    /// - Throws: An error if the shutdown operation fails.
    public func shutdown() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = Shutdown()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }
}
