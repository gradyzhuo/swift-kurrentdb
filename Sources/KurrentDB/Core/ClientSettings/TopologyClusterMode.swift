//
//  TopologyClusterMode.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/2/7.
//

import Foundation
import NIOCore

/// Cluster topology mode describing how the client discovers and connects to KurrentDB nodes.
public enum TopologyClusterMode: Sendable {
    /// Single-node topology connecting directly to one endpoint.
    case standalone(endpoint: Endpoint)
    /// DNS-based discovery using a single domain endpoint to locate cluster members.
    case dns(domain: Endpoint)
    /// Gossip-based discovery using a known list of seed endpoints.
    case seeds([Endpoint])
}
