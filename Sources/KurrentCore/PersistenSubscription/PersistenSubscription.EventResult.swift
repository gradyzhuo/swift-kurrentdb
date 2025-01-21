//
//  PersistenSubscription.SubscriptionEvent.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/13.
//

extension PersistentSubscription{
    public struct EventResult : Sendable{
        public let event: ReadEvent
        public let retryCount: Int32

        package init(event: ReadEvent, retryCount: Int32) {
            self.event = event
            self.retryCount = retryCount
        }
    }
}
