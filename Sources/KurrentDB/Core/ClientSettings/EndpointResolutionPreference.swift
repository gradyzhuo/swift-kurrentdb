//
//  EndpointResolutionPreference.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/8/24.
//

/// Determines which endpoint a discovered node connects through.
public enum EndpointResolutionPreference: Sendable {
    /// Connect via the address gossip reports for the selected member.
    /// Required for `.seeds` / `.dns`, where the selected member may differ
    /// from the endpoint that was queried.
    case gossipReported

    /// Always connect via the endpoint the caller configured, ignoring the
    /// address gossip reports. Safe only for `.standalone`, where the queried
    /// endpoint and the selected member are guaranteed to be the same node —
    /// e.g. containers behind NAT/port-mapping whose self-reported address
    /// isn't reachable from outside.
    case userConfigured
}
