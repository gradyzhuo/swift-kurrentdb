//
//  ClientSettings.TopologyClusterMode.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/2/7.
//

import Foundation
import NIOCore

public enum TopologyClusterMode: Sendable {
    public enum NodePreference: String, Sendable {
        case leader
        case follower
        case random
        case readOnlyReplica = "readonlyreplica"
    }

    case standalone(at: Endpoint)
    case gossipCluster(seeds: [Endpoint], nodePreference: NodePreference, timeout: TimeAmount)

    static func gossipCluster(endpoints: [Endpoint], nodePreference: NodePreference) -> Self {
        .gossipCluster(seeds: endpoints, nodePreference: nodePreference, timeout: DEFAULT_GOSSIP_TIMEOUT)
    }
}

extension TopologyClusterMode.NodePreference {
    func priority(state: Gossip.VNodeState)->Int{
        switch self {
        case .leader:
            switch state {
            case .leader: 0
            case .follower: 1
            case .readOnlyReplica: 2
            case .preReadOnlyReplica: 3
            case .readOnlyLeaderless: 4
            default: .max
            }
        case .follower:
            switch state {
            case .follower: 0
            case .leader: 1
            case .readOnlyReplica: 2
            case .preReadOnlyReplica: 3
            case .readOnlyLeaderless: 4
            default: .max
            }
        case .readOnlyReplica:
            switch state {
            case .readOnlyReplica: 0
            case .preReadOnlyReplica: 1
            case .readOnlyLeaderless: 2
            case .leader: 3
            case .follower: 4
            default: .max
            }
        case .random:
            0
        }
    }

}
