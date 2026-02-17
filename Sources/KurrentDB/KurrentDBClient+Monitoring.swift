//
//  KurrentDBClient+Monitoring.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/17.
//

// MARK: - Monitoring Operations

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
