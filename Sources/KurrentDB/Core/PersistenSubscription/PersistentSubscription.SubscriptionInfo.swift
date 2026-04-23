//
//  PersistentSubscription.SubscriptionInfo.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/12.
//

import GRPCEncapsulates

extension PersistentSubscription {
    /// Snapshot of the server-side state and configuration for a persistent subscription.
    public struct SubscriptionInfo: GRPCBridge {
        package typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_SubscriptionInfo
        /// Stream name or `$all` that this subscription reads from.
        public let eventSource: String
        /// Consumer group name for this subscription.
        public let groupName: String
        /// Human-readable status reported by the server (e.g., "Live", "CatchUp").
        public let status: String
        /// Active consumer connections to this subscription.
        public let connections: [ConnectionInfo]
        /// Average number of events processed per second across all connections.
        public let averagePerSecond: Int32
        /// Total number of events delivered since the subscription was created.
        public let totalItems: Int64
        /// Number of events delivered since the last measurement snapshot.
        public let countSinceLastMeasurement: Int64
        /// Position of the last successfully checkpointed event.
        public let lastCheckpointedEventPosition: String
        /// Position of the most recent event known to this subscription.
        public let lastKnownEventPosition: String
        /// Whether linked events are resolved to their original event.
        public let resolveLinkTos: Bool
        /// Stream position or revision from which this subscription started reading.
        public let startFrom: String
        /// Milliseconds before an unacknowledged message times out and is retried.
        public let messageTimeoutMilliseconds: Int32
        /// Whether in-depth latency statistics are enabled for this subscription.
        public let extraStatistics: Bool
        /// Maximum number of delivery retries before a message is parked.
        public let maxRetryCount: Int32
        /// Capacity of the in-memory buffer for live events.
        public let liveBufferSize: Int32
        /// Total capacity of the internal event buffer.
        public let bufferSize: Int32
        /// Number of events fetched per page when reading historical events.
        public let readBatchSize: Int32
        /// Minimum time in milliseconds between checkpoint writes.
        public let checkPointAfterMilliseconds: Int32
        /// Minimum number of events required before a checkpoint is written.
        public let minCheckPointCount: Int32
        /// Maximum number of events allowed between checkpoint writes.
        public let maxCheckPointCount: Int32
        /// Current number of events in the read buffer.
        public let readBufferCount: Int32
        /// Current number of events in the live buffer.
        public let liveBufferCount: Int64
        /// Current number of events in the retry buffer.
        public let retryBufferCount: Int32
        /// Total number of messages currently in flight across all connections.
        public let totalInFlightMessages: Int32
        /// Total number of messages awaiting acknowledgement.
        public let outstandingMessageCount: Int32
        /// Raw string identifying the consumer dispatch strategy.
        public let namedConsumerStrategy: String
        /// Maximum number of concurrent subscribers; 0 means unlimited.
        public let maxSubscriberCount: Int32
        /// Number of messages currently held in the parked message queue.
        public let parkedMessageCount: Int64

        package init(
            eventSource: String,
            groupName: String,
            status: String, connections: [ConnectionInfo],
            averagePerSecond: Int32,
            totalItems: Int64,
            countSinceLastMeasurement: Int64,
            lastCheckpointedEventPosition: String,
            lastKnownEventPosition: String,
            resolveLinkTos: Bool,
            startFrom: String,
            messageTimeoutMilliseconds: Int32,
            extraStatistics: Bool,
            maxRetryCount: Int32,
            liveBufferSize: Int32,
            bufferSize: Int32,
            readBatchSize: Int32,
            checkPointAfterMilliseconds: Int32,
            minCheckPointCount: Int32,
            maxCheckPointCount: Int32,
            readBufferCount: Int32,
            liveBufferCount: Int64,
            retryBufferCount: Int32,
            totalInFlightMessages: Int32,
            outstandingMessageCount: Int32,
            namedConsumerStrategy: String,
            maxSubscriberCount: Int32,
            parkedMessageCount: Int64
        ) {
            self.eventSource = eventSource
            self.groupName = groupName
            self.status = status
            self.connections = connections
            self.averagePerSecond = averagePerSecond
            self.totalItems = totalItems
            self.countSinceLastMeasurement = countSinceLastMeasurement
            self.lastCheckpointedEventPosition = lastCheckpointedEventPosition
            self.lastKnownEventPosition = lastKnownEventPosition
            self.resolveLinkTos = resolveLinkTos
            self.startFrom = startFrom
            self.messageTimeoutMilliseconds = messageTimeoutMilliseconds
            self.extraStatistics = extraStatistics
            self.maxRetryCount = maxRetryCount
            self.liveBufferSize = liveBufferSize
            self.bufferSize = bufferSize
            self.readBatchSize = readBatchSize
            self.checkPointAfterMilliseconds = checkPointAfterMilliseconds
            self.minCheckPointCount = minCheckPointCount
            self.maxCheckPointCount = maxCheckPointCount
            self.readBufferCount = readBufferCount
            self.liveBufferCount = liveBufferCount
            self.retryBufferCount = retryBufferCount
            self.totalInFlightMessages = totalInFlightMessages
            self.outstandingMessageCount = outstandingMessageCount
            self.namedConsumerStrategy = namedConsumerStrategy
            self.maxSubscriberCount = maxSubscriberCount
            self.parkedMessageCount = parkedMessageCount
        }

        package init(from message: UnderlyingMessage) {
            let connections: [ConnectionInfo] = message.connections.map {
                .init(
                    from: $0.from,
                    username: $0.username,
                    averageItemsPerSecond: $0.averageItemsPerSecond,
                    totalItems: $0.totalItems,
                    countSinceLastMeasurement: $0.countSinceLastMeasurement,
                    obervedMeasurements: $0.observedMeasurements.map {
                        .init(key: $0.key, value: $0.value)
                    },
                    availableSlots: $0.availableSlots,
                    inFlightMessages: $0.inFlightMessages,
                    connectionName: $0.connectionName
                )
            }

            self.init(
                eventSource: message.eventSource,
                groupName: message.groupName,
                status: message.status,
                connections: connections,
                averagePerSecond: message.averagePerSecond,
                totalItems: message.totalItems,
                countSinceLastMeasurement: message.countSinceLastMeasurement,
                lastCheckpointedEventPosition: message.lastCheckpointedEventPosition,
                lastKnownEventPosition: message.lastKnownEventPosition,
                resolveLinkTos: message.resolveLinkTos,
                startFrom: message.startFrom,
                messageTimeoutMilliseconds: message.messageTimeoutMilliseconds,
                extraStatistics: message.extraStatistics,
                maxRetryCount: message.maxRetryCount,
                liveBufferSize: message.liveBufferSize,
                bufferSize: message.bufferSize,
                readBatchSize: message.readBatchSize,
                checkPointAfterMilliseconds: message.checkPointAfterMilliseconds,
                minCheckPointCount: message.minCheckPointCount,
                maxCheckPointCount: message.maxCheckPointCount,
                readBufferCount: message.readBufferCount,
                liveBufferCount: message.liveBufferCount,
                retryBufferCount: message.retryBufferCount,
                totalInFlightMessages: message.totalInFlightMessages,
                outstandingMessageCount: message.outstandingMessagesCount,
                namedConsumerStrategy: message.namedConsumerStrategy,
                maxSubscriberCount: message.maxSubscriberCount,
                parkedMessageCount: message.parkedMessageCount
            )
        }
    }
}
