//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/22.
//

import Foundation
import GRPCEncapsulates


extension EventStore_Client_PersistentSubscriptions_CreateReq.Settings: PersistentSubscriptionsGRPCSettings {
    
    public static func make(settings: PersistentSubscriptionsClient.Settings) -> Self {
        return .with{
            $0.resolveLinks = settings.resolveLink
            $0.extraStatistics = settings.extraStatistics
            $0.maxRetryCount = settings.maxRetryCount
            $0.minCheckpointCount = settings.checkpointCount.lowerBound
            $0.maxSubscriberCount = settings.checkpointCount.upperBound
            $0.maxSubscriberCount = settings.maxSubscriberCount
            $0.liveBufferSize = settings.liveBufferSize
            $0.readBatchSize = settings.readBatchSize
            $0.historyBufferSize = settings.historyBufferSize

            switch settings.checkpointAfter{
            case .ms(let ms):
                $0.checkpointAfterMs = ms
            case .ticks(let ticks):
                $0.checkpointAfterTicks = ticks
            }

            switch settings.messageTimeout {
            case .ticks(let int64):
                $0.messageTimeoutTicks = int64
            case .ms(let int32):
                $0.messageTimeoutMs = int32
            }
            $0.consumerStrategy = settings.consumerStrategy.rawValue
        }
        

    }
    
}


extension EventStore_Client_PersistentSubscriptions_UpdateReq.Settings: PersistentSubscriptionsGRPCSettings {
    public static func make(settings: PersistentSubscriptionsClient.Settings) -> Self {
        return .with{
            $0.resolveLinks = settings.resolveLink
            $0.extraStatistics = settings.extraStatistics
            $0.maxRetryCount = settings.maxRetryCount
            $0.minCheckpointCount = settings.checkpointCount.lowerBound
            $0.maxSubscriberCount = settings.checkpointCount.upperBound
            $0.maxSubscriberCount = settings.maxSubscriberCount
            $0.liveBufferSize = settings.liveBufferSize
            $0.readBatchSize = settings.readBatchSize
            $0.historyBufferSize = settings.historyBufferSize

            switch settings.checkpointAfter{
            case .ms(let ms):
                $0.checkpointAfterMs = ms
            case .ticks(let ticks):
                $0.checkpointAfterTicks = ticks
            }

            switch settings.messageTimeout {
            case .ticks(let int64):
                $0.messageTimeoutTicks = int64
            case .ms(let int32):
                $0.messageTimeoutMs = int32
            }
        }
    }
}


extension EventStore_Client_PersistentSubscriptions_CreateReq.AllOptions.FilterOptions{
    public static func make(with filter: StreamClient.FilterOption) -> Self {
        return .with {
            switch filter.window {
            case .count:
                $0.count = .init()
            case let .max(max):
                $0.max = max
            }
            
            switch filter.type {
            case let .streamName(regex):
                $0.streamIdentifier = .with {
                    $0.regex = regex
                    $0.prefix = filter.prefixes
                }
            case let .eventType(regex):
                $0.eventType = .with {
                    $0.regex = regex
                    $0.prefix = filter.prefixes
                }
            }
            
            $0.checkpointIntervalMultiplier = filter.checkpointIntervalMultiplier
        }
    }
}


