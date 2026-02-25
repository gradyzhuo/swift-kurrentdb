//
//  KurrentDBClient+V1Operations.swift
//  swift-kurrentdb
//
//  Compatibility layer — convenience methods for server operations.
//  Prefer the target-based API: client.operations(of:)
//

import KurrentDB

@available(*, deprecated, message: "Use the target-based API instead: client.operations(of:)")
extension KurrentDBClient {
    /// Starts a scavenge operation to reclaim disk space by removing deleted events and tombstones.
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws(KurrentError) -> Operations<ScavengeOperations>.ScavengeResponse {
        try await operations(of: .scavenge).startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }

    /// Stops a running scavenge operation.
    public func stopScavenge(scavengeId: String) async throws(KurrentError) -> Operations<ActiveScavenge>.ScavengeResponse {
        try await operations(of: .activeScavenge(scavengeId: scavengeId)).stopScavenge()
    }

    /// Merges database indexes to optimize query performance.
    public func mergeIndexes() async throws(KurrentError) {
        try await operations(of: .system).mergeIndexes()
    }

    /// Restarts the persistent subscriptions subsystem.
    public func restartPersistentSubscriptions() async throws(KurrentError) {
        try await operations(of: .system).restartPersistentSubscriptions()
    }

    /// Shuts down the KurrentDB server gracefully.
    public func shutdown() async throws(KurrentError) {
        try await operations(of: .system).shutdown()
    }

    /// Resigns the current node from its role in the cluster.
    public func resignNode() async throws(KurrentError) {
        try await operations(of: .node).resignNode()
    }

    /// Sets the priority of the current node for leader election.
    public func setNodePriority(priority: Int32) async throws(KurrentError) {
        try await operations(of: .node).setNodePriority(priority: priority)
    }
}
