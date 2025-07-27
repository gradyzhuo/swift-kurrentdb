//
//  KurrentDBClient+ServerOperations.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides methods for server operations.
extension KurrentDBClient {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> Operations.ScavengeResponse {
        try await operations.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }

    public func stopScavenge(scavengeId: String) async throws -> Operations.ScavengeResponse {
        try await operations.stopScavenge(scavengeId: scavengeId)
    }
}
