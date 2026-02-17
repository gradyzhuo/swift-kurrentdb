//
//  KurrentDBClient+ServerOperations.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Server Maintenance Operations

extension KurrentDBClient {
    /// Creates an operations interface for a specific target type.
    ///
    /// Returns a type-safe `Operations` instance scoped to the given target.
    /// The target determines which operations are available at compile time.
    ///
    /// ## Available Targets
    ///
    /// | Target | Factory | Available Operations |
    /// |--------|---------|---------------------|
    /// | `ScavengeOperations` | `.scavenge` | `startScavenge(threadCount:startFromChunk:)` |
    /// | `ActiveScavenge` | `.activeScavenge(scavengeId:)` | `stopScavenge()` |
    /// | `SystemOperations` | `.system` | `shutdown()`, `mergeIndexes()`, `restartPersistentSubscriptions()` |
    /// | `NodeOperations` | `.node` | `resignNode()`, `setNodePriority(priority:)` |
    ///
    /// ## Example
    ///
    /// ```swift
    /// // System operations
    /// try await client.operations(of: .system).shutdown()
    /// try await client.operations(of: .system).mergeIndexes()
    /// try await client.operations(of: .system).restartPersistentSubscriptions()
    ///
    /// // Scavenge operations
    /// let response = try await client.operations(of: .scavenge)
    ///     .startScavenge(threadCount: 2, startFromChunk: 0)
    /// try await client.operations(of: .activeScavenge(scavengeId: response.scavengeId))
    ///     .stopScavenge()
    ///
    /// // Node operations
    /// try await client.operations(of: .node).resignNode()
    /// try await client.operations(of: .node).setNodePriority(priority: 10)
    /// ```
    ///
    /// - Parameter target: The operations target specifying the scope and available operations.
    ///
    /// - Returns: A configured `Operations` instance with methods constrained by the target type.
    ///
    /// - SeeAlso: `OperationsTarget`, `ScavengeOperations`, `ActiveScavenge`, `SystemOperations`, `NodeOperations`
    public func operations<Target: OperationsTarget>(of target: Target) -> Operations<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}

extension KurrentDBClient {
    /// Starts a scavenge operation to reclaim disk space by removing deleted events and tombstones.
    ///
    /// Scavenging is a background maintenance operation that physically removes deleted events from
    /// database chunks, reclaiming disk space and improving read performance. The operation runs
    /// asynchronously on the server and may take significant time to complete depending on database
    /// size and disk I/O performance. Scavenges can be run concurrently with normal operations but
    /// may impact server performance during execution.
    ///
    /// ## Scavenge Process
    ///
    /// The scavenge operation:
    /// 1. Identifies deleted events and expired maxAge/maxCount streams
    /// 2. Creates new chunk files without deleted data
    /// 3. Replaces old chunks with compacted versions
    /// 4. Reclaims disk space by removing old chunk files
    /// 5. Updates indexes to reflect new chunk positions
    ///
    /// ## Thread Count Configuration
    ///
    /// The `threadCount` parameter controls parallelism:
    /// - **Higher values**: Faster scavenge completion but higher CPU/disk I/O usage
    /// - **Lower values**: Slower completion but less impact on normal operations
    /// - **Recommended**: 1-4 threads for production systems
    /// - **Maximum**: Limited by server configuration
    ///
    /// ## Starting Position
    ///
    /// The `startFromChunk` parameter allows resuming interrupted scavenges:
    /// - **0**: Start from the beginning (most common)
    /// - **Specific chunk**: Resume from a previously scavenged position
    /// - Use this to continue if a previous scavenge was stopped
    ///
    /// ## Use Cases
    ///
    /// - Reclaiming disk space after deleting large streams
    /// - Optimizing read performance by compacting chunk files
    /// - Scheduled maintenance during low-traffic periods
    /// - Recovering from disk space constraints
    /// - Cleaning up after maxAge/maxCount stream expirations
    ///
    /// ## Performance Impact
    ///
    /// During scavenging:
    /// - Read latency may increase due to disk I/O contention
    /// - Write throughput generally unaffected
    /// - CPU utilization increases based on thread count
    /// - Disk space usage temporarily increases (new chunks created before old ones deleted)
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Start a scavenge with 2 threads from the beginning
    /// let response = try await client.startScavenge(
    ///     threadCount: 2,
    ///     startFromChunk: 0
    /// )
    ///
    /// print("Scavenge started with ID: \(response.scavengeId)")
    /// print("Result: \(response.result)")
    ///
    /// // Monitor scavenge progress (if supported by server)
    /// // Poll server status or check logs
    ///
    /// // Optionally stop the scavenge if needed
    /// if needsToStop {
    ///     let stopResponse = try await client.stopScavenge(
    ///         scavengeId: response.scavengeId
    ///     )
    ///     print("Scavenge stopped at chunk: \(stopResponse.result)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - threadCount: Number of parallel threads to use for scavenging. Higher values complete
    ///     faster but increase server load. Typical range: 1-4. Must be positive.
    ///   - startFromChunk: Chunk number to begin scavenging from. Use 0 to start from the beginning,
    ///     or specify a chunk number to resume a previously interrupted scavenge.
    ///
    /// - Returns: A `ScavengeResponse` containing the unique scavenge operation ID and initial status.
    ///   Use this ID to stop the scavenge if needed.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative or operations permissions.
    ///   `KurrentError.alreadyExists` if a scavenge is already running (server typically allows only one).
    ///   `KurrentError.invalidArgument` if thread count or chunk number is invalid.
    ///   `KurrentError.unavailable` if the server cannot start a scavenge operation.
    ///
    /// - Note: Only users in the `$admins` or `$ops` groups can start scavenge operations.
    ///   Most servers allow only one scavenge operation at a time.
    ///
    /// - Warning: Scavenges can be resource-intensive and may impact server performance.
    ///   Schedule scavenges during maintenance windows or low-traffic periods. Ensure adequate
    ///   disk space is available (scavenge temporarily doubles space usage for chunks being compacted).
    ///
    /// - Warning: Do not restart the server while a scavenge is running, as this may leave the
    ///   database in an inconsistent state. Always stop the scavenge gracefully first.
    ///
    /// - SeeAlso: `stopScavenge(scavengeId:)`
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws(KurrentError) -> Operations<ScavengeOperations>.ScavengeResponse {
        try await operations(of: .scavenge).startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }

    /// Stops a running scavenge operation, allowing it to complete gracefully at its current position.
    ///
    /// Stops an in-progress scavenge operation, ensuring it completes its current chunk processing
    /// before halting. The scavenge will save its position, allowing it to be resumed later from
    /// where it stopped by using the `startFromChunk` parameter with the last completed chunk number.
    ///
    /// ## Graceful Shutdown
    ///
    /// When stopped:
    /// - The current chunk being processed completes
    /// - The scavenge position is saved
    /// - Server resources are released
    /// - The operation can be resumed later
    ///
    /// ## Resuming Stopped Scavenges
    ///
    /// To resume a stopped scavenge:
    /// 1. Note the last completed chunk from the stop response
    /// 2. Call `startScavenge(threadCount:startFromChunk:)` with that chunk number
    /// 3. The scavenge continues from where it left off
    ///
    /// ## Use Cases
    ///
    /// - Stopping scavenges during peak traffic to reduce server load
    /// - Halting scavenges before planned server maintenance
    /// - Pausing resource-intensive operations temporarily
    /// - Stopping scavenges that are taking longer than expected
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Start a scavenge
    /// let startResponse = try await client.startScavenge(
    ///     threadCount: 2,
    ///     startFromChunk: 0
    /// )
    ///
    /// let scavengeId = startResponse.scavengeId
    ///
    /// // Later, if needed, stop the scavenge
    /// let stopResponse = try await client.stopScavenge(scavengeId: scavengeId)
    /// print("Scavenge stopped. Result: \(stopResponse.result)")
    ///
    /// // Resume later from where it stopped
    /// // (Extract chunk number from logs or monitoring)
    /// try await client.startScavenge(
    ///     threadCount: 2,
    ///     startFromChunk: lastCompletedChunk
    /// )
    /// ```
    ///
    /// - Parameter scavengeId: The unique identifier of the scavenge operation to stop. This ID
    ///   is returned by `startScavenge(threadCount:startFromChunk:)`.
    ///
    /// - Returns: A `ScavengeResponse` containing the final status and position of the stopped scavenge.
    ///
    /// - Throws: `KurrentError.notFound` if no scavenge operation exists with the specified ID.
    ///   `KurrentError.accessDenied` if the user lacks administrative or operations permissions.
    ///   `KurrentError.invalidArgument` if the scavenge ID is invalid or malformed.
    ///
    /// - Note: Stopping a scavenge does not rollback any work already completed. Chunks that have
    ///   been scavenged remain in their compacted state.
    ///
    /// - SeeAlso: `startScavenge(threadCount:startFromChunk:)`
    public func stopScavenge(scavengeId: String) async throws(KurrentError) -> Operations<ActiveScavenge>.ScavengeResponse {
        try await operations(of: .activeScavenge(scavengeId: scavengeId)).stopScavenge()
    }
}

// MARK: - System Operations

extension KurrentDBClient {
    /// Merges database indexes to optimize query performance.
    ///
    /// Index merging consolidates index segments, reducing disk I/O and improving
    /// query performance. This operation can be resource-intensive.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.mergeIndexes()
    /// ```
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the operation cannot be performed.
    ///
    /// - Note: Only users in the `$admins` or `$ops` groups can perform this operation.
    ///
    /// - SeeAlso: `shutdown()`, `restartPersistentSubscriptions()`
    public func mergeIndexes() async throws(KurrentError) {
        try await operations(of: .system).mergeIndexes()
    }

    /// Restarts the persistent subscriptions subsystem.
    ///
    /// Stops all persistent subscriptions, clears in-memory state, and reinitializes
    /// the subscription manager. All subscription groups reload from persistent storage.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.restartPersistentSubscriptions()
    /// ```
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the subsystem cannot be restarted.
    ///
    /// - Note: Only users in the `$admins` or `$ops` groups can perform this operation.
    ///
    /// - SeeAlso: `mergeIndexes()`, `shutdown()`
    public func restartPersistentSubscriptions() async throws(KurrentError) {
        try await operations(of: .system).restartPersistentSubscriptions()
    }

    /// Shuts down the KurrentDB server gracefully.
    ///
    /// Initiates a graceful shutdown, completing in-flight operations and persisting
    /// state before terminating the server process.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.shutdown()
    /// ```
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///
    /// - Warning: This operation terminates the server. Ensure all clients are prepared
    ///   for disconnection before calling this method.
    ///
    /// - SeeAlso: `mergeIndexes()`, `restartPersistentSubscriptions()`
    public func shutdown() async throws(KurrentError) {
        try await operations(of: .system).shutdown()
    }
}

// MARK: - Node Operations

extension KurrentDBClient {
    /// Resigns the current node from its role in the cluster.
    ///
    /// If the node is a leader, it steps down and triggers a new election. This is useful
    /// for graceful maintenance or cluster rebalancing.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.resignNode()
    /// ```
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the operation cannot be performed.
    ///
    /// - SeeAlso: `setNodePriority(priority:)`
    public func resignNode() async throws(KurrentError) {
        try await operations(of: .node).resignNode()
    }

    /// Sets the priority of the current node for leader election.
    ///
    /// Higher priority nodes are more likely to be elected as leader. Use this to
    /// influence cluster leadership distribution.
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.setNodePriority(priority: 10)
    /// ```
    ///
    /// - Parameter priority: The priority value to set. Higher values increase election likelihood.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.invalidArgument` if the priority value is invalid.
    ///
    /// - SeeAlso: `resignNode()`
    public func setNodePriority(priority: Int32) async throws(KurrentError) {
        try await operations(of: .node).setNodePriority(priority: priority)
    }
}
