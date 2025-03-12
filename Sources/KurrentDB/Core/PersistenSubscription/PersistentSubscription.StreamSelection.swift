//
//  PersistentSubscription.StreamSelection.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    public enum StreamSelection {
        case all(position: Cursor<StreamPosition>, filterOption: SubscriptionFilter? = nil)
        case specified(identifier: StreamIdentifier, revision: Cursor<UInt64>)

        public static func specified(identifier: StreamIdentifier) -> Self {
            .specified(identifier: identifier, revision: .end)
        }

        public static func specified(streamName: String, revision _: Cursor<UInt64> = .end) -> Self {
            .specified(identifier: .init(name: streamName), revision: .end)
        }
    }
}

