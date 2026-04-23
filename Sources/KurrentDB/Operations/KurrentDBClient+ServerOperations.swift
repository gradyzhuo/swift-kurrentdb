//
//  KurrentDBClient+ServerOperations.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Server Operations Factory Methods

extension KurrentDBClient {
    /// Returns a server operations interface scoped to the given target.
    ///
    /// The target constrains which operations are available at compile time:
    /// - `.system` — `shutdown()`, `mergeIndexes()`, `restartPersistentSubscriptions()`
    /// - `.scavenge` — `startScavenge(threadCount:startFromChunk:)`
    /// - `.activeScavenge(scavengeId:)` — `stopScavenge()`
    /// - `.node` — `resignNode()`, `setNodePriority(priority:)`
    ///
    /// ```swift
    /// try await client.operations(of: .system).mergeIndexes()
    ///
    /// let response = try await client.operations(of: .scavenge)
    ///     .startScavenge(threadCount: 2, startFromChunk: 0)
    /// try await client.operations(of: .activeScavenge(scavengeId: response.scavengeId))
    ///     .stopScavenge()
    /// ```
    ///
    /// - Parameter target: Operations target specifying scope and capabilities.
    /// - Returns: An ``Operations`` instance constrained by the target type.
    public func operations<Target: OperationsTarget>(of target: Target) -> Operations<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}
