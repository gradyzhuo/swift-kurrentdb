//
//  ClientSettings.TopologyClusterMode.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/2/7.
//

import Foundation

public enum TopologyClusterMode: Sendable {
    public enum NodePreference: String, Sendable {
        case leader
        case follower
        case random
        case readOnlyReplica = "readonlyreplica"
    }

    case singleNode(at: Endpoint)
    case dnsDiscovery(from: Endpoint, interval: TimeInterval, maxAttempts: Int)
    case gossipCluster(endpoints: [Endpoint], nodePreference: NodePreference, timeout: TimeInterval)

    static func gossipCluster(endpoints: [Endpoint], nodePreference: NodePreference) -> Self {
        .gossipCluster(endpoints: endpoints, nodePreference: nodePreference, timeout: DEFAULT_GOSSIP_TIMEOUT)
    }
}
