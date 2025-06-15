import Foundation
import GRPCEncapsulates

extension Gossip {
    public enum VNodeState: Sendable, Equatable {
        package typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo.VNodeState

        case initializing
        case discoverLeader
        case unknown
        case preReplica
        case catchingUp
        case clone
        case follower
        case preLeader
        case leader
        case manager
        case shuttingDown
        case shutdown
        case readOnlyLeaderless
        case preReadOnlyReplica
        case readOnlyReplica
        case resigningLeader
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
