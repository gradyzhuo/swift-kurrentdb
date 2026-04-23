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

/// gRPC service for KurrentDB server administration scoped to a specific operations target.
public final class Operations<Target: OperationsTarget>: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_Operations_Operations.Client<HTTP2ClientTransport.Posix>

    internal let selector: NodeSelector
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup

    /// Target specifying the scope and available operations for this service instance.
    public let target: Target

    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - Scavenge Creation Operations

extension Operations where Target: ScavengeCreatable {
    /// Starts a scavenge operation to reclaim disk space by removing deleted events.
    ///
    /// - Parameters:
    ///   - threadCount: Number of parallel threads to use; higher values are faster but increase load.
    ///   - startFromChunk: Chunk number to start from; use `0` to begin at the first chunk.
    /// - Returns: A response containing the scavenge ID and initial status.
    /// - Throws: `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.alreadyExists` if a scavenge is already running.
    ///   `KurrentError.invalidArgument` if parameters are out of range.
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws(KurrentError) -> StartScavenge.Response {
        let node = try await selector.select()
        let usecase = StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        return try await usecase.perform(node: node, callOptions: callOptions)
    }
}

// MARK: - Scavenge Control Operations

extension Operations where Target: ScavengeControllable {
    /// Stops the target scavenge operation, saving its position for potential resumption.
    ///
    /// - Returns: A response containing the final status and chunk position.
    /// - Throws: `KurrentError.notFound` if no running scavenge matches the target ID.
    ///   `KurrentError.accessDenied` if the caller lacks administrative permissions.
    public func stopScavenge() async throws(KurrentError) -> StopScavenge.Response {
        let node = try await selector.select()
        let usecase = StopScavenge(scavengeId: target.scavengeId)
        return try await usecase.perform(node: node, callOptions: callOptions)
    }
}

// MARK: - System Operations

extension Operations where Target: SystemControllable {
    /// Merges database index segments to reduce disk I/O and improve query performance.
    ///
    /// - Throws: `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.unavailable` if the operation cannot be performed.
    public func mergeIndexes() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = MergeIndexes()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Restarts the persistent subscriptions subsystem, reloading all subscription groups from storage.
    ///
    /// - Throws: `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.unavailable` if the subsystem cannot be restarted.
    public func restartPersistentSubscriptions() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = RestartPersistentSubscriptions()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Initiates a graceful server shutdown.
    ///
    /// - Throws: `KurrentError.accessDenied` if the caller lacks administrative permissions.
    /// - Warning: Terminates the server process. Ensure all clients are prepared for disconnection.
    public func shutdown() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = Shutdown()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }
}

// MARK: - Node Operations

extension Operations where Target: NodeControllable {
    /// Resigns the current node from its cluster role, triggering a new election if it is leader.
    ///
    /// - Throws: `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.unavailable` if the operation cannot be performed.
    public func resignNode() async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = ResignNode()
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }

    /// Sets the current node's election priority; higher values increase the chance of becoming leader.
    ///
    /// - Parameter priority: Priority value for leader election.
    /// - Throws: `KurrentError.accessDenied` if the caller lacks administrative permissions.
    ///   `KurrentError.invalidArgument` if the priority value is invalid.
    public func setNodePriority(priority: Int32) async throws(KurrentError) {
        let node = try await selector.select()
        let usecase = SetNodePriority(priority: priority)
        _ = try await usecase.perform(node: node, callOptions: callOptions)
    }
}
