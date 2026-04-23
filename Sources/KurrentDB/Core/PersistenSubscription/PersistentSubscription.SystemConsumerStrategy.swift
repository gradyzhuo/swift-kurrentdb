//
//  PersistentSubscription.SystemConsumerStrategy.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    /// Strategy used by the server to dispatch events to competing consumers.
    public enum SystemConsumerStrategy: RawRepresentable, Sendable {
        public typealias RawValue = String

        /// Fills one consumer's buffer before moving to the next in round-robin order.
        case dispatchToSingle

        /// Distributes events evenly across all connected consumers.
        case roundRobin

        /// Routes events to consumers by hashing the source stream identifier, reducing ordering conflicts.
        case pinned

        /// Routes events to consumers by hashing the correlation identifier.
        case pinnedByCorrelation

        /// A custom strategy identified by the given raw string value.
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
