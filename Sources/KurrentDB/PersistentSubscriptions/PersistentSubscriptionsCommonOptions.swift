//
//  PersistentSubscriptionsCommonOptions.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2024/3/22.
//

import Foundation
import GRPCEncapsulates

protocol PersistentSubscriptionsCommonOptions: EventStoreOptions {
    var settings: PersistentSubscription.Settings { set get }
}

extension PersistentSubscriptionsCommonOptions {
    @discardableResult
    public mutating func set(resolveLinks: Bool) -> Self {
        withCopy { copied in
            copied.settings.resolveLink = resolveLinks
        }
    }

    @discardableResult
    public mutating func set(extraStatistics: Bool) -> Self {
        withCopy { copied in
            copied.settings.extraStatistics = extraStatistics
        }
    }

    @discardableResult
    public mutating func set(maxRetryCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.maxRetryCount = maxRetryCount
        }
    }

    @discardableResult
    public mutating func set(minCheckpointCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.checkpointCount = minCheckpointCount ... settings.checkpointCount.upperBound
        }
    }

    @discardableResult
    public mutating func set(maxCheckpointCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.checkpointCount = settings.checkpointCount.lowerBound ... maxCheckpointCount
        }
    }

    @discardableResult
    public mutating func set(maxSubscriberCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.maxSubscriberCount = maxSubscriberCount
        }
    }

    @discardableResult
    public mutating func set(liveBufferSize: Int32) -> Self {
        withCopy { copied in
            copied.settings.liveBufferSize = liveBufferSize
        }
    }

    @discardableResult
    public mutating func set(readBatchSize: Int32) -> Self {
        withCopy { copied in
            copied.settings.readBatchSize = readBatchSize
        }
    }

    @discardableResult
    public mutating func set(historyBufferSize: Int32) -> Self {
        withCopy { copied in
            copied.settings.historyBufferSize = historyBufferSize
        }
    }

    @discardableResult
    public mutating func set(messageTimeout timeout: TimeSpan) -> Self {
        withCopy { copied in
            copied.settings.messageTimeout = timeout
        }
    }

    @discardableResult
    public mutating func setCheckpoint(after span: TimeSpan) -> Self {
        withCopy { copied in
            copied.settings.checkpointAfter = span
        }
    }
}
