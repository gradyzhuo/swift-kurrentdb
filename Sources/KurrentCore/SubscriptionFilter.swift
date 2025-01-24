//
//  SubscriptionFilter.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/23.
//
import GRPCEncapsulates

public struct SubscriptionFilter: Buildable {
    public enum Window: Sendable {
        case count
        case max(UInt32)
    }

    public enum FilterType: Sendable {
        case streamName(regex: String)
        case eventType(regex: String)
    }

    public internal(set) var type: FilterType
    public internal(set) var window: Window
    public internal(set) var prefixes: [String]
    public internal(set) var checkpointIntervalMultiplier: UInt32

    init(type: FilterType, window: Window = .count, prefixes: [String] = []) {
        self.type = type
        self.window = window
        self.prefixes = prefixes
        checkpointIntervalMultiplier = .max
    }

    @discardableResult
    public static func onStreamName(regex: String) -> Self {
        .init(type: .streamName(regex: regex))
    }

    @discardableResult
    public static func onEventType(regex: String) -> Self {
        .init(type: .eventType(regex: regex))
    }

    @discardableResult
    public func set(max maxCount: UInt32) -> Self {
        withCopy { options in
            options.window = .max(maxCount)
        }
    }

    @discardableResult
    public func set(checkpointIntervalMultiplier multiplier: UInt32) -> Self {
        withCopy { options in
            options.checkpointIntervalMultiplier = multiplier
        }
    }

    @discardableResult
    public func add(prefix: String) -> Self {
        withCopy { options in
            options.prefixes.append(prefix)
        }
    }
}
