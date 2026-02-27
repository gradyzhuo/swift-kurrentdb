//
//  KurrentDBClient+ServerOperations.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Server Operations Factory Methods

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
