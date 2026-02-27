//
//  KurrentDBClient+Monitoring.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/17.
//

// MARK: - Monitoring Operations

/// Provides access to core service instances.
extension KurrentDBClient {
    /// Accesses the cluster monitoring service for health checks and status information.
    ///
    /// The monitoring service provides real-time information about the KurrentDB cluster,
    /// including node health, cluster state, and operational metrics. This is useful for
    /// building health dashboards, implementing service health checks, or monitoring
    /// cluster performance.
    ///
    /// The returned `Monitoring` instance is pre-configured with:
    /// - The client's `NodeSelector` for automatic endpoint selection
    /// - The client's `defaultCallOptions` for consistent request behavior
    /// - The shared `EventLoopGroup` for efficient I/O operations
    ///
    /// ## Common Use Cases
    ///
    /// - Health check endpoints in web services
    /// - Monitoring dashboards and alerting systems
    /// - Cluster state verification before critical operations
    /// - Performance metrics collection
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Check cluster health
    /// let health = try await client.monitoring.health()
    /// print("Cluster is healthy: \(health.isHealthy)")
    /// ```
    ///
    /// - Returns: A configured `Monitoring` service instance.
    ///
    /// - Note: All monitoring operations are read-only and safe to call frequently.
    ///   However, excessive polling may impact cluster performance.
    ///
    /// - SeeAlso: `Monitoring`
    public var monitoring: Monitoring {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

}


extension KurrentDBClient {
    /// Retrieves real-time server statistics as an asynchronous stream.
    ///
    /// Returns a stream of stat snapshots that periodically refreshes at the specified interval.
    /// Each snapshot contains key-value pairs of server metrics including disk usage, memory,
    /// queue lengths, and other runtime statistics.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let stats = try await client.stats()
    ///
    /// for try await snapshot in stats {
    ///     for (key, value) in snapshot.stats {
    ///         print("\(key): \(value)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - useMetadata: Whether to include metadata in the response. Defaults to `false`.
    ///   - refreshTimePeriodInMs: The interval in milliseconds between stat refreshes. Defaults to `10000` (10 seconds).
    ///
    /// - Returns: An `AsyncThrowingStream` of ``Monitoring/Stats/Response`` snapshots.
    ///
    /// - Throws: `KurrentError` if the stats request fails.
    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws(KurrentError) -> Monitoring.Stats.Responses {
        let monitoring = Monitoring(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
        return try await monitoring.stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
    }
}
