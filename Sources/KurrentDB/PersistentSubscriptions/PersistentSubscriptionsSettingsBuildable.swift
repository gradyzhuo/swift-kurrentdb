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
    /// Enables resolution of link events for the persistent subscription.
    ///
    /// - Returns: The builder instance with link resolution enabled.
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

    

    /// Sets the consumer strategy for the persistent subscription.
    ///
    /// - Parameter value: The system consumer strategy to use for distributing events among subscribers.
    /// - Returns: The builder instance with the updated consumer strategy.
    @discardableResult
    public func consumerStrategy(_ value: PersistentSubscription.SystemConsumerStrategy) -> Self {
        withCopy { $0.settings.consumerStrategy = value }
    }
}

extension PersistentSubscriptionsSettingsBuildable where SettingsType == PersistentSubscription.UpdateSettings {
    /// Enables resolution of link events for the persistent subscription.
    ///
    /// - Returns: The builder instance with link resolution enabled.
    @discardableResult
    public func resolveLink() -> Self {
        withCopy { $0.settings.resolveLink = true }
    }

    /// Enables the collection of extra statistics for the persistent subscription.
    ///
    /// - Returns: The builder instance with extra statistics enabled.
    @discardableResult
    public func extraStatistics() -> Self {
        withCopy { $0.settings.extraStatistics = true }
    }

    /// Sets the message timeout duration for the persistent subscription.
    ///
    /// - Parameter value: The maximum time to allow a message to be processed before considering it timed out.
    /// - Returns: The builder instance with the updated message timeout.
    @discardableResult
    public func messageTimeout(_ value: TimeSpan) -> Self {
        withCopy { $0.settings.messageTimeout = value }
    }

    /// Sets the maximum number of retry attempts for message delivery before a message is considered to have failed.
    ///
    /// - Parameter value: The maximum number of retries allowed for a message.
    /// - Returns: The builder instance with the updated retry count.
    @discardableResult
    public func maxRetryCount(_ value: Int32) -> Self {
        withCopy { $0.settings.maxRetryCount = value }
    }

    /// Sets the checkpoint count range for the persistent subscription.
    ///
    /// - Parameter value: The inclusive range specifying the minimum and maximum number of events between checkpoints.
    /// - Returns: The builder instance with the updated checkpoint count range.
    @discardableResult
    public func checkpoint(count value: ClosedRange<Int32>) -> Self {
        withCopy { $0.settings.checkpointCount = value }
    }
    
    /// Sets the minimum time interval before a checkpoint is written for the persistent subscription.
    ///
    /// - Parameter value: The duration to wait before writing a checkpoint.
    /// - Returns: The builder instance with the updated checkpoint interval.
    @discardableResult
    public func checkpoint(after value: TimeSpan) -> Self {
        withCopy { $0.settings.checkpointAfter = value }
    }

    /// Sets the maximum number of subscribers allowed for the persistent subscription.
    ///
    /// - Parameter value: The maximum number of subscribers.
    /// - Returns: The builder instance with the updated subscriber count.
    @discardableResult
    public func maxSubscriberCount(_ value: Int32) -> Self {
        withCopy { $0.settings.maxSubscriberCount = value }
    }

    /// Sets the live buffer size for the persistent subscription.
    ///
    /// - Parameter value: The number of events to buffer when reading live.
    /// - Returns: The builder instance with the updated live buffer size.
    @discardableResult
    public func liveBufferSize(_ value: Int32) -> Self {
        withCopy { $0.settings.liveBufferSize = value }
    }

    /// Sets the read batch size for the persistent subscription.
    ///
    /// - Parameter value: The number of events to read in each batch.
    /// - Returns: The builder instance with the updated read batch size.
    @discardableResult
    public func readBatchSize(_ value: Int32) -> Self {
        withCopy { $0.settings.readBatchSize = value }
    }

    /// Sets the history buffer size for the persistent subscription.
    ///
    /// - Parameter value: The number of events to keep in the history buffer.
    /// - Returns: The builder instance with the updated history buffer size.
    @discardableResult
    public func historyBufferSize(_ value: Int32) -> Self {
        withCopy { $0.settings.historyBufferSize = value }
    }

}

// MARK: - Deprecated
extension PersistentSubscriptionsSettingsBuildable where SettingsType == PersistentSubscription.CreateSettings {
    /// Sets whether to resolve link events when creating a persistent subscription (deprecated).
    ///
    /// - Parameter resolveLinks: If `true`, the subscription will resolve link events.
    /// - Returns: The modified builder instance.
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
