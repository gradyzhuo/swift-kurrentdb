//
//  KurrentDBClient+Gossip.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/16.
//

// MARK: - Gossip Operations

extension KurrentDBClient {
    /// Reads the current cluster topology via the gossip protocol.
    ///
    /// Queries cluster nodes directly to retrieve information about all members in the cluster,
    /// including their state, health status, and network endpoints. This is useful for
    /// monitoring cluster health, debugging connectivity issues, or implementing custom
    /// node selection logic.
    ///
    /// ## Cluster Member Information
    ///
    /// Each `MemberInfo` contains:
    /// - **instanceId**: Unique identifier for the node
    /// - **state**: Current node state (leader, follower, readOnlyReplica, etc.)
    /// - **isAlive**: Whether the node is currently responsive
    /// - **httpEndPoint**: The node's HTTP endpoint for client connections
    ///
    /// ## Example
    ///
    /// ```swift
    /// let members = try await client.readGossip()
    /// for member in members {
    ///     print("Node \(member.instanceId): \(member.state), alive: \(member.isAlive)")
    ///     print("  Endpoint: \(member.httpEndPoint.host):\(member.httpEndPoint.port)")
    /// }
    ///
    /// // Find the current leader
    /// if let leader = members.first(where: { $0.state == .leader && $0.isAlive }) {
    ///     print("Leader: \(leader.httpEndPoint.host):\(leader.httpEndPoint.port)")
    /// }
    /// ```
    ///
    /// - Parameter timeout: The maximum duration to wait for the gossip response.
    ///   Defaults to the client's configured gossip timeout.
    ///
    /// - Returns: An array of `Gossip.MemberInfo` representing all known cluster members.
    ///
    /// - Throws: `KurrentError` if the gossip request fails or all endpoints are unreachable.
    ///
    /// - SeeAlso: `Gossip.MemberInfo`, `Gossip.VNodeState`
    public func readGossip(timeout: Duration? = nil) async throws -> [Gossip.MemberInfo] {
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
