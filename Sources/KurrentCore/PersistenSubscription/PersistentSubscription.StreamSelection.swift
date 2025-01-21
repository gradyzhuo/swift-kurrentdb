//
//  PersistentSubscription.StreamSelection.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    public enum StreamSelection {
        case all(position: Cursor<Stream.Position>, filterOption: Stream.SubscriptionFilter? = nil)
        case specified(identifier: Stream.Identifier, revision: Cursor<UInt64>)

        public static func specified(identifier: Stream.Identifier) -> Self {
            .specified(identifier: identifier, revision: .end)
        }

        public static func specified(streamName: String, revision _: Cursor<UInt64> = .end) -> Self {
            .specified(identifier: .init(name: streamName), revision: .end)
        }
    }
}
