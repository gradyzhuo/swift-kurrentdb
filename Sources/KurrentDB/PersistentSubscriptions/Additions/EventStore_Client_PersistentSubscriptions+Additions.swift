//
//  EventStore_Client_PersistentSubscriptions+Additions.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2024/3/22.
//

import Foundation
import GRPCEncapsulates

extension EventStore_Client_PersistentSubscriptions_CreateReq.Settings {
    /// Creates a gRPC persistent subscription settings message from the provided create settings.
    ///
    /// Maps all relevant properties from `PersistentSubscription.CreateSettings` to the corresponding gRPC fields, including checkpoint and timeout values.
    ///
    /// - Parameter settings: The persistent subscription creation settings to convert.
    /// - Returns: A gRPC `Settings` message populated with the provided settings.
    package static func make(settings: PersistentSubscription.CreateSettings) -> Self {
        .with {
            $0.resolveLinks = settings.resolveLink
            $0.extraStatistics = settings.extraStatistics
            $0.maxRetryCount = settings.maxRetryCount
            $0.minCheckpointCount = settings.checkpointCount.lowerBound
            $0.maxSubscriberCount = settings.checkpointCount.upperBound
            $0.maxSubscriberCount = settings.maxSubscriberCount
            $0.liveBufferSize = settings.liveBufferSize
            $0.readBatchSize = settings.readBatchSize
            $0.historyBufferSize = settings.historyBufferSize

            switch settings.checkpointAfter {
            case let .ms(ms):
                $0.checkpointAfterMs = ms
            case let .ticks(ticks):
                $0.checkpointAfterTicks = ticks
            }

            switch settings.messageTimeout {
            case let .ticks(int64):
                $0.messageTimeoutTicks = int64
            case let .ms(int32):
                $0.messageTimeoutMs = int32
            }
            $0.consumerStrategy = settings.consumerStrategy.rawValue
        }
    }
}

extension EventStore_Client_PersistentSubscriptions_UpdateReq.Settings {
    /// Creates a `Settings` instance for updating a persistent subscription from the provided update settings.
    ///
    /// Only fields with non-nil values in `settings` are set in the resulting `Settings` object. This includes options such as link resolution, extra statistics, retry counts, checkpoint counts, subscriber limits, buffer sizes, and timeout values.
    ///
    /// - Parameter settings: The update settings to map to the gRPC request settings.
    /// - Returns: A `Settings` instance populated with the specified update options.
    package static func from(settings: PersistentSubscription.UpdateSettings) -> Self {
        .with {
            if let resolveLink = settings.resolveLink {
                $0.resolveLinks = resolveLink
            }
            
            if let extraStatistics = settings.extraStatistics {
                $0.extraStatistics = extraStatistics
            }

            if let maxRetryCount = settings.maxRetryCount {
                $0.maxRetryCount = maxRetryCount
            }

            if let checkpointCount = settings.checkpointCount {
                $0.minCheckpointCount = checkpointCount.lowerBound
                $0.maxSubscriberCount = checkpointCount.upperBound
            }

            if let maxSubscriberCount = settings.maxSubscriberCount {
                $0.maxSubscriberCount = maxSubscriberCount
            }
            if let liveBufferSize = settings.liveBufferSize {
                $0.liveBufferSize = liveBufferSize
            }
            if let readBatchSize = settings.readBatchSize {
                $0.readBatchSize = readBatchSize
            }
            if let historyBufferSize = settings.historyBufferSize {
                $0.historyBufferSize = historyBufferSize
            }
            if let checkpointAfter = settings.checkpointAfter {
                switch checkpointAfter {
                case let .ms(ms):
                    $0.checkpointAfterMs = ms
                case let .ticks(ticks):
                    $0.checkpointAfterTicks = ticks
                }
            }
            if let messageTimeout = settings.messageTimeout {
                switch messageTimeout {
                case let .ticks(int64):
                    $0.messageTimeoutTicks = int64
                case let .ms(int32):
                    $0.messageTimeoutMs = int32
                }
            }
        }
    }
}

extension EventStore_Client_PersistentSubscriptions_CreateReq.AllOptions.FilterOptions {
    package static func make(with filter: SubscriptionFilter) -> Self {
        .with {
            switch filter.window {
            case .count:
                $0.count = .init()
            case let .max(max):
                $0.max = max
            }

            switch filter.type {
            case .streamName:
                $0.streamIdentifier = .with {
                    if let regex = filter.regex{
                        $0.regex = regex
                    }
                    
                    $0.prefix = filter.prefixes
                }
            case .eventType:
                $0.eventType = .with {
                    if let regex = filter.regex{
                        $0.regex = regex
                    }
                    $0.prefix = filter.prefixes
                }
            }

            $0.checkpointIntervalMultiplier = filter.checkpointIntervalMultiplier
        }
    }
}
