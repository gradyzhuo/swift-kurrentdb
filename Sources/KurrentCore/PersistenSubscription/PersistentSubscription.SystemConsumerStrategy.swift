//
//  PersistentSubscription.SystemConsumerStrategy.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    public enum SystemConsumerStrategy: RawRepresentable, Sendable {
        public typealias RawValue = String

        /// Distributes events to a single client until the bufferSize is reached.
        /// After which the next client is selected in a round robin style,
        /// and the process is repeated.
        case dispatchToSingle

        /// Distributes events to all clients evenly. If the client buffer-size
        /// is reached the client is ignored until events are
        /// acknowledged/not acknowledged.
        case roundRobin

        /// For use with an indexing projection such as the system $by_category
        /// projection. Event Store inspects event for its source stream id,
        /// hashing the id to one of 1024 buckets assigned to individual clients.
        /// When a client disconnects it's buckets are assigned to other clients.
        /// When a client connects, it is assigned some of the existing buckets.
        /// This naively attempts to maintain a balanced workload.
        /// The main aim of this strategy is to decrease the likelihood of
        /// concurrency and ordering issues while maintaining load balancing.
        /// This is not a guarantee, and you should handle the usual ordering
        /// and concurrency issues.
        case pinned

        case pinnedByCorrelation

        case custom(String)

        public var rawValue: String {
            switch self {
            case .dispatchToSingle:
                "DispatchToSingle"
            case .roundRobin:
                "RoundRobin"
            case .pinned:
                "Pinned"
            case .pinnedByCorrelation:
                "PinnedByCorrelation"
            case let .custom(value):
                value
            }
        }

        public init?(rawValue: String) {
            switch rawValue {
            case Self.dispatchToSingle.rawValue:
                self = .dispatchToSingle
            case Self.roundRobin.rawValue:
                self = .roundRobin
            case Self.pinned.rawValue:
                self = .pinned
            case Self.pinnedByCorrelation.rawValue:
                self = .pinnedByCorrelation
            default:
                self = .custom(rawValue)
            }
        }
    }
}
