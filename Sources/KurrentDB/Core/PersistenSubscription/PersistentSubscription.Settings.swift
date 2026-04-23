//
//  PersistentSubscription.Settings.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/12.
//

extension PersistentSubscription {
    /// Settings for creating a new persistent subscription.
    public struct CreateSettings: Sendable {
        /// Whether linked events are resolved to their original event.
        public var resolveLink: Bool

        /// Whether in-depth latency statistics are tracked for this subscription.
        public var extraStatistics: Bool

        /// Time in milliseconds before an unacknowledged message is considered timed out and retried.
        public var messageTimeout: TimeSpan

        /// Maximum number of delivery retries before a message is parked.
        public var maxRetryCount: Int32

        /// Inclusive range of events that must be processed before a checkpoint is written.
        public var checkpointCount: ClosedRange<Int32>

        /// Maximum number of subscribers allowed to connect concurrently; 0 means unlimited.
        public var maxSubscriberCount: Int32

        /// Size of the in-memory buffer for live events arriving in real time.
        public var liveBufferSize: Int32

        /// Number of events fetched per page when reading historical events.
        public var readBatchSize: Int32

        /// Number of historical events held in the cache while paging through history.
        public var historyBufferSize: Int32

        /// Minimum time in milliseconds between checkpoint writes.
        public var checkpointAfter: TimeSpan

        /// Strategy used to distribute events among connected consumers.
        public var consumerStrategy: SystemConsumerStrategy = .roundRobin

        public init(
            resolveLink: Bool = false,
            extraStatistics: Bool = false,
            messageTimeout: TimeSpan = .ms(30),
            maxRetryCount: Int32 = 10,
            checkpointCount: ClosedRange<Int32> = 10 ... 1000,
            maxSubscriberCount: Int32 = 0,
            liveBufferSize: Int32 = 500,
            readBatchSize: Int32 = 20,
            historyBufferSize: Int32 = 500,
            checkpointAfter: TimeSpan = .ms(2),
            consumerStrategy: SystemConsumerStrategy = .roundRobin
        ) {
            self.resolveLink = resolveLink
            self.extraStatistics = extraStatistics
            self.messageTimeout = messageTimeout
            self.maxRetryCount = maxRetryCount
            self.checkpointCount = checkpointCount
            self.maxSubscriberCount = maxSubscriberCount
            self.liveBufferSize = liveBufferSize
            self.readBatchSize = readBatchSize
            self.historyBufferSize = historyBufferSize
            self.checkpointAfter = checkpointAfter
            self.consumerStrategy = consumerStrategy
        }
    }

    /// Settings for updating an existing persistent subscription; all fields are optional.
    public struct UpdateSettings: Sendable {
        /// Whether linked events are resolved to their original event.
        public var resolveLink: Bool?

        /// Whether in-depth latency statistics are tracked for this subscription.
        public var extraStatistics: Bool?

        /// Time in milliseconds before an unacknowledged message is considered timed out and retried.
        public var messageTimeout: TimeSpan?

        /// Maximum number of delivery retries before a message is parked.
        public var maxRetryCount: Int32?

        /// Inclusive range of events that must be processed before a checkpoint is written.
        public var checkpointCount: ClosedRange<Int32>?

        /// Maximum number of subscribers allowed to connect concurrently; 0 means unlimited.
        public var maxSubscriberCount: Int32?

        /// Size of the in-memory buffer for live events arriving in real time.
        public var liveBufferSize: Int32?

        /// Number of events fetched per page when reading historical events.
        public var readBatchSize: Int32?

        /// Number of historical events held in the cache while paging through history.
        public var historyBufferSize: Int32?

        /// Minimum time in milliseconds between checkpoint writes.
        public var checkpointAfter: TimeSpan?

        package init(){ }
        
        mutating func update(from info: PersistentSubscription.SubscriptionInfo) {
            self.resolveLink = info.resolveLinkTos
            self.extraStatistics = info.extraStatistics
            self.messageTimeout = .ms(Int32(info.messageTimeoutMilliseconds))
            self.maxRetryCount = info.maxRetryCount
            self.checkpointCount = info.minCheckPointCount ... info.maxCheckPointCount
            self.maxSubscriberCount = info.maxSubscriberCount
            self.liveBufferSize = info.liveBufferSize
            self.readBatchSize = info.readBatchSize
            self.historyBufferSize = info.bufferSize
            self.checkpointAfter = .ms(Int32(info.checkPointAfterMilliseconds))
        }
    }
}
