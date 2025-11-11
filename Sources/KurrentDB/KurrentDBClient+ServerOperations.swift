//
//  KurrentDBClient+ServerOperations.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides methods for server operations.
extension KurrentDBClient {
    /// Starts a scavenge operation on the server.
    ///
    /// - Parameters:
    ///   - threadCount: The number of threads to use for the scavenge operation.
    ///   - startFromChunk: The chunk number to start scavenging from.
    /// - Returns: A response containing details about the scavenge operation.
    /// - Throws: An error if the scavenge operation fails to start.
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> Operations.ScavengeResponse {
        try await operations.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }

    /// Stops a running scavenge operation.
    ///
    /// - Parameters:
    ///   - scavengeId: The identifier of the scavenge operation to stop.
    /// - Returns: A response containing details about the stopped scavenge operation.
    /// - Throws: An error if the scavenge operation fails to stop.
    public func stopScavenge(scavengeId: String) async throws -> Operations.ScavengeResponse {
        try await operations.stopScavenge(scavengeId: scavengeId)
    }
}
