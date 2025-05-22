//
//  KurrentDBClient+ServerOperations.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides methods for server operations.
extension KurrentDBClient {
    /// Starts a scavenge operation to reclaim disk space.
    ///
    /// - Parameters:
    ///   - threadCount: The number of threads to use for the scavenge operation.
    ///   - startFromChunk: The chunk number from which to start scavenging.
    /// - Returns: An `Operations.ScavengeResponse` containing details about the operation.
    /// - Throws: An error if the scavenge operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> Operations.ScavengeResponse {
        return try await operations.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }

    /// Stops an ongoing scavenge operation.
    ///
    /// - Parameter scavengeId: The identifier of the scavenge operation to stop.
    /// - Returns: An `Operations.ScavengeResponse` indicating the result.
    /// - Throws: An error if the scavenge operation cannot be stopped.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func stopScavenge(scavengeId: String) async throws -> Operations.ScavengeResponse {
        return try await operations.stopScavenge(scavengeId: scavengeId)
    }
}
