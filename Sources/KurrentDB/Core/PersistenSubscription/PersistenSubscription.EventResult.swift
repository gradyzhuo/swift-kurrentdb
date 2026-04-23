//
//  PersistenSubscription.EventResult.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/13.
//

extension PersistentSubscription {
    /// An event delivered by a persistent subscription together with its retry metadata.
    public struct EventResult: Sendable {
        /// The event read from the stream.
        public let event: ReadEvent
        /// Number of times this event has been retried after a previous nack or timeout.
        public let retryCount: Int32

        package init(event: ReadEvent, retryCount: Int32) {
            self.event = event
            self.retryCount = retryCount
        }
    }
}


/// Provides stream-position metadata so that `EventResult` can be used as the
/// generic parameter of ``PersistentSubscriptions/Subscription``.
extension PersistentSubscription.EventResult: SubscriptionEventResult {
    /// Stream revision of the underlying recorded event.
    public var revision: UInt64? {
        event.record.revision
    }

    /// Commit position of the event in the `$all` stream.
    public var position: StreamPosition? {
        event.commitPosition
    }
}
