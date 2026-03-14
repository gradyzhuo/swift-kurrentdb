//
//  KurrentDBClient+Monitoring.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/17.
//

// MARK: - Monitoring Operations

extension KurrentDBClient {
    /// Accesses the cluster monitoring service for health checks and status information.
    ///
    /// ```swift
    /// let health = try await client.monitoring.health()
    /// ```
    ///
    /// - SeeAlso: ``Monitoring``
    public var monitoring: Monitoring {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Retrieves real-time server statistics as an asynchronous stream.
    ///
    /// Each snapshot contains key-value pairs of server metrics (disk usage, memory, queue lengths, etc.)
    /// refreshed at the specified interval.
    ///
    /// ```swift
    /// for try await snapshot in try await client.stats() {
    ///     for (key, value) in snapshot.stats {
    ///         print("\(key): \(value)")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - useMetadata: Include metadata in the response. Defaults to `false`.
    ///   - refreshTimePeriodInMs: Refresh interval in milliseconds. Defaults to `10000` (10s).
    ///
    /// - Returns: An async stream of ``Monitoring/Stats/Response`` snapshots.
    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws(KurrentError) -> Monitoring.Stats.Responses {
        let monitoring = Monitoring(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
        return try await monitoring.stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
    }
}
