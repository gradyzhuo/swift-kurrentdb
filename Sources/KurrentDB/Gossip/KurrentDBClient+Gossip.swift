//
//  KurrentDBClient+Gossip.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/2/16.
//

// MARK: - Gossip Operations

extension KurrentDBClient {
    /// Reads the current cluster topology via the gossip protocol.
    ///
    /// Returns information about all cluster members including their state (leader, follower,
    /// readOnlyReplica), health status, and network endpoints.
    ///
    /// ```swift
    /// let members = try await client.readCluster()
    /// for member in members {
    ///     print("Node \(member.instanceId): \(member.state), alive: \(member.isAlive)")
    /// }
    ///
    /// // Find the current leader
    /// if let leader = members.first(where: { $0.state == .leader && $0.isAlive }) {
    ///     print("Leader: \(leader.httpEndPoint)")
    /// }
    /// ```
    ///
    /// - Parameter timeout: Maximum wait duration. Defaults to the client's configured gossip timeout.
    /// - Returns: An array of ``Gossip/MemberInfo`` for all known cluster members.
    /// - Throws: ``KurrentError`` if the gossip request fails or all endpoints are unreachable.
    public func readCluster(timeout: Duration? = nil) async throws(KurrentError) -> [Gossip.MemberInfo] {
        let candidates = switch settings.clusterMode {
        case let .standalone(endpoint):
            [endpoint]
        case let .dns(endpoint):
            [endpoint]
        case let .seeds(candidates):
            candidates
        }

        let gossipTimeout = timeout ?? settings.gossipTimeout
        for candidate in candidates {
            let gossip = Gossip(
                endpoint: candidate,
                settings: settings,
                callOptions: defaultCallOptions,
                eventLoopGroup: eventLoopGroup
            )
            if let members = try? await gossip.read(timeout: gossipTimeout), !members.isEmpty {
                return members
            }
        }

        return try await Gossip(
            endpoint: candidates[0],
            settings: settings,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup
        ).read(timeout: gossipTimeout)
    }
}
