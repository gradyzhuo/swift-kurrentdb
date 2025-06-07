//
//  PersistentSubscriptionsCommonOptions.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2024/3/22.
//

import Foundation
import GRPCEncapsulates

public protocol PersistentSubscriptionsSettingsBuildable: Buildable {
    associatedtype SettingsType
    var settings: SettingsType { set get }
}

extension PersistentSubscriptionsSettingsBuildable where SettingsType == PersistentSubscription.CreateSettings {
    @discardableResult
    public func resolveLink() -> Self {
        withCopy { $0.settings.resolveLink = true }
    }

    @discardableResult
    public func extraStatistics() -> Self {
        withCopy { $0.settings.extraStatistics = true }
    }

    @discardableResult
    public func messageTimeout(_ value: TimeSpan) -> Self {
        withCopy { $0.settings.messageTimeout = value }
    }

    @discardableResult
    public func maxRetryCount(_ value: Int32) -> Self {
        withCopy { $0.settings.maxRetryCount = value }
    }

    @discardableResult
    public func checkpoint(count value: ClosedRange<Int32>) -> Self {
        withCopy { $0.settings.checkpointCount = value }
    }
    
    @discardableResult
    public func checkpoint(after value: TimeSpan) -> Self {
        withCopy { $0.settings.checkpointAfter = value }
    }

    @discardableResult
    public func maxSubscriberCount(_ value: Int32) -> Self {
        withCopy { $0.settings.maxSubscriberCount = value }
    }

    @discardableResult
    public func liveBufferSize(_ value: Int32) -> Self {
        withCopy { $0.settings.liveBufferSize = value }
    }

    @discardableResult
    public func readBatchSize(_ value: Int32) -> Self {
        withCopy { $0.settings.readBatchSize = value }
    }

    @discardableResult
    public func historyBufferSize(_ value: Int32) -> Self {
        withCopy { $0.settings.historyBufferSize = value }
    }

    

    @discardableResult
    public func consumerStrategy(_ value: PersistentSubscription.SystemConsumerStrategy) -> Self {
        withCopy { $0.settings.consumerStrategy = value }
    }
}

extension PersistentSubscriptionsSettingsBuildable where SettingsType == PersistentSubscription.UpdateSettings {
    @discardableResult
    public func resolveLink() -> Self {
        withCopy { $0.settings.resolveLink = true }
    }

    @discardableResult
    public func extraStatistics() -> Self {
        withCopy { $0.settings.extraStatistics = true }
    }

    @discardableResult
    public func messageTimeout(_ value: TimeSpan) -> Self {
        withCopy { $0.settings.messageTimeout = value }
    }

    @discardableResult
    public func maxRetryCount(_ value: Int32) -> Self {
        withCopy { $0.settings.maxRetryCount = value }
    }

    @discardableResult
    public func checkpoint(count value: ClosedRange<Int32>) -> Self {
        withCopy { $0.settings.checkpointCount = value }
    }
    
    @discardableResult
    public func checkpoint(after value: TimeSpan) -> Self {
        withCopy { $0.settings.checkpointAfter = value }
    }

    @discardableResult
    public func maxSubscriberCount(_ value: Int32) -> Self {
        withCopy { $0.settings.maxSubscriberCount = value }
    }

    @discardableResult
    public func liveBufferSize(_ value: Int32) -> Self {
        withCopy { $0.settings.liveBufferSize = value }
    }

    @discardableResult
    public func readBatchSize(_ value: Int32) -> Self {
        withCopy { $0.settings.readBatchSize = value }
    }

    @discardableResult
    public func historyBufferSize(_ value: Int32) -> Self {
        withCopy { $0.settings.historyBufferSize = value }
    }

}

// MARK: - Deprecated
extension PersistentSubscriptionsSettingsBuildable where SettingsType == PersistentSubscription.CreateSettings {
    @discardableResult
    @available(*, deprecated)
    public mutating func set(resolveLinks: Bool) -> Self {
        withCopy { copied in
            copied.settings.resolveLink = resolveLinks
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(extraStatistics: Bool) -> Self {
        withCopy { copied in
            copied.settings.extraStatistics = extraStatistics
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(maxRetryCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.maxRetryCount = maxRetryCount
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(minCheckpointCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.checkpointCount = minCheckpointCount ... settings.checkpointCount.upperBound
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(maxCheckpointCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.checkpointCount = settings.checkpointCount.lowerBound ... maxCheckpointCount
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(maxSubscriberCount: Int32) -> Self {
        withCopy { copied in
            copied.settings.maxSubscriberCount = maxSubscriberCount
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(liveBufferSize: Int32) -> Self {
        withCopy { copied in
            copied.settings.liveBufferSize = liveBufferSize
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(readBatchSize: Int32) -> Self {
        withCopy { copied in
            copied.settings.readBatchSize = readBatchSize
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(historyBufferSize: Int32) -> Self {
        withCopy { copied in
            copied.settings.historyBufferSize = historyBufferSize
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func set(messageTimeout timeout: TimeSpan) -> Self {
        withCopy { copied in
            copied.settings.messageTimeout = timeout
        }
    }

    @discardableResult
    @available(*, deprecated)
    public mutating func setCheckpoint(after span: TimeSpan) -> Self {
        withCopy { copied in
            copied.settings.checkpointAfter = span
        }
    }
}
