//
//  KurrentDBClient+Monitoring.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/17.
//

// MARK: - Monitoring Operations

extension KurrentDBClient {
    /// Monitoring service for querying real-time KurrentDB server statistics.
    public var monitoring: Monitoring {
        .init(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Streams server statistics snapshots from the monitoring service.
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
    ///   - useMetadata: Include metadata fields in each snapshot. Defaults to `false`.
    ///   - refreshTimePeriodInMs: Interval between snapshots in milliseconds. Defaults to `10000` (10 s).
    /// - Returns: An async stream of ``Monitoring/Stats/Response`` snapshots.
    /// - Throws: `KurrentError.accessDenied` if the caller lacks permission to read stats.
    ///   `KurrentError.unavailable` if the server cannot be reached.
    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws(KurrentError) -> Monitoring.Stats.Responses {
        let monitoring = Monitoring(selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
        return try await monitoring.stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
    }
}
