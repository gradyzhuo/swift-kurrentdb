//
//  PersistentSubscriptionsClient.GetInfo.SubscriptionInfo.swift
//
//
//  Created by Grady Zhuo on 2024/5/15.
//

import Foundation
import GRPCEncapsulates

extension PersistentSubscriptionsClient.GetInfo {
    public struct SubscriptionInfo: GRPCBridge {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_SubscriptionInfo
        public let eventSource: String
        public let groupName: String
        public let status: String
        public let connections: [ConnectionInfo]
        public let averagePerSecond: Int32
        public let totalItems: Int64
        public let countSinceLastMeasurement: Int64
        public let lastCheckpointedEventPosition: String
        public let lastKnownEventPosition: String
        public let resolveLinkTos: Bool
        public let startFrom: String
        public let messageTimeoutMilliseconds: Int32
        public let extraStatistics: Bool
        public let maxRetryCount: Int32
        public let liveBufferSize: Int32
        public let bufferSize: Int32
        public let readBatchSize: Int32
        public let checkPointAfterMilliseconds: Int32
        public let minCheckPointCount: Int32
        public let maxCheckPointCount: Int32
        public let readBufferCount: Int32
        public let liveBufferCount: Int64
        public let retryBufferCount: Int32
        public let totalInFlightMessages: Int32
        public let outstandingMessageCount: Int32
        public let namedConsumerStrategy: String
        public let maxSubscriberCount: Int32
        public let parkedMessageCount: Int64

        init(
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

        init(from message: UnderlyingMessage) {
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
