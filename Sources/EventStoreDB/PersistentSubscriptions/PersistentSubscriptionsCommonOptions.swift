//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/22.
//

import Foundation
import GRPCEncapsulates

protocol PersistentSubscriptionsCommonOptions: EventStoreOptions {
    var settings: PersistentSubscriptionsClient.Settings { set get }
}

extension PersistentSubscriptionsCommonOptions{
    @discardableResult
    public mutating func set(resolveLinks: Bool) -> Self {
        settings.resolveLink = resolveLinks
        return self
    }
    
    @discardableResult
    public mutating func set(extraStatistics: Bool) -> Self {
        settings.extraStatistics = extraStatistics
        return self
    }

    @discardableResult
    public mutating func set(maxRetryCount: Int32) -> Self {
        settings.maxRetryCount = maxRetryCount
        return self
    }
    
    @discardableResult
    public mutating func set(minCheckpointCount: Int32) -> Self {
        settings.checkpointCount = minCheckpointCount ... settings.checkpointCount.upperBound
        return self
    }

    @discardableResult
    public mutating func set(maxCheckpointCount: Int32) -> Self {
        settings.checkpointCount = settings.checkpointCount.lowerBound ... maxCheckpointCount
        return self
    }

    @discardableResult
    public mutating func set(maxSubscriberCount: Int32) -> Self {
        settings.maxSubscriberCount = maxSubscriberCount
        return self
    }

    @discardableResult
    public mutating func set(liveBufferSize: Int32) -> Self {
        settings.liveBufferSize = liveBufferSize
        return self
    }

    @discardableResult
    public mutating func set(readBatchSize: Int32) -> Self {
        settings.readBatchSize = readBatchSize
        return self
    }

    @discardableResult
    public mutating func set(historyBufferSize: Int32) -> Self {
        settings.historyBufferSize = historyBufferSize
        return self
    }

    @discardableResult
    public mutating func set(messageTimeout timeout: TimeSpan) -> Self {
        settings.messageTimeout = timeout
        return self
    }

    @discardableResult
    public mutating func setCheckpoint(after span: TimeSpan) -> Self {
        settings.checkpointAfter = span
        return self
    }
}
