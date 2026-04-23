import Foundation
import GRPCEncapsulates

extension Gossip {
    /// Represents the lifecycle state of a virtual node (VNode) in the Kurrent cluster.
    public enum VNodeState: Sendable, Equatable {
        package typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo.VNodeState

        /// Node is starting up and not yet ready to serve requests.
        case initializing
        /// Node is searching for the current cluster leader.
        case discoverLeader
        /// Node state cannot be determined.
        case unknown
        /// Node is preparing to become a replica before full replication begins.
        case preReplica
        /// Node is catching up by replicating historical data from the leader.
        case catchingUp
        /// Legacy node role: replicated data from the leader without participating in quorum. Superseded by ``readOnlyReplica``.
        case clone
        /// Node is a fully synchronized follower replicating from the leader.
        case follower
        /// Node is transitioning to become the cluster leader.
        case preLeader
        /// Node is the active cluster leader accepting all writes.
        case leader
        /// Node is operating as a cluster manager.
        case manager
        /// Node has begun its shutdown sequence and is winding down.
        case shuttingDown
        /// Node has fully stopped and is no longer serving requests.
        case shutdown
        /// Read-only replica that has lost contact with the leader; replication is paused and reads may be stale.
        case readOnlyLeaderless
        /// Node is preparing to become a read-only replica.
        case preReadOnlyReplica
        /// Node is a read-only replica, accepting reads but not writes.
        case readOnlyReplica
        /// Node is actively stepping down from the leader role.
        case resigningLeader
        /// Node state value not recognized by this client version.
        case UNRECOGNIZED(Int)

        package init(from message: UnderlyingMessage) {
            switch message {
            case .initializing:
                self = .initializing
            case .discoverLeader:
                self = .discoverLeader
            case .unknown:
                self = .unknown
            case .preReplica:
                self = .preReplica
            case .catchingUp:
                self = .catchingUp
            case .clone:
                self = .clone
            case .follower:
                self = .follower
            case .preLeader:
                self = .preLeader
            case .leader:
                self = .leader
            case .manager:
                self = .manager
            case .shuttingDown:
                self = .shuttingDown
            case .shutdown:
                self = .shutdown
            case .readOnlyLeaderless:
                self = .readOnlyLeaderless
            case .preReadOnlyReplica:
                self = .preReadOnlyReplica
            case .readOnlyReplica:
                self = .readOnlyReplica
            case .resigningLeader:
                self = .resigningLeader
            case let .UNRECOGNIZED(enumValue):
                self = .UNRECOGNIZED(enumValue)
            }
        }
    }
}

extension Gossip.VNodeState: CaseIterable {
    public static var allCases: [Self] {
        [
            .initializing,
            .discoverLeader,
            .unknown,
            .preReplica,
            .catchingUp,
            .clone,
            .follower,
            .preLeader,
            .leader,
            .manager,
            .shuttingDown,
            .shutdown,
            .readOnlyLeaderless,
        ]
    }
}
