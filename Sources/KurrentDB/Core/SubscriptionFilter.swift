//
//  SubscriptionFilter.swift
//  KurrentCore
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
        case streamName
        case eventType
    }

    public internal(set) var type: FilterType
    public internal(set) var regex: String?
    public internal(set) var window: Window
    public internal(set) var prefixes: [String]
    public internal(set) var checkpointIntervalMultiplier: UInt32

    init(type: FilterType, regex: String? = nil, window: Window = .count, prefixes: [String] = []) {
        self.type = type
        self.regex = regex
        self.window = window
        self.prefixes = prefixes
        checkpointIntervalMultiplier = .max
    }

    @discardableResult
    public func max(_ maxCount: UInt32) -> Self {
        withCopy { options in
            options.window = .max(maxCount)
        }
    }

    @discardableResult
    public func checkpointIntervalMultiplier(_ multiplier: UInt32) -> Self {
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

// MARK: - Constructor on StreamName

extension SubscriptionFilter {
    public static func onStreamName(regex: String) -> Self {
        .init(type: .streamName, regex: regex)
    }

    public static func onStreamName(prefix: String...) -> Self {
        .onStreamName(prefixes: prefix)
    }

    public static func onStreamName(prefixes: [String]) -> Self {
        .init(type: .streamName, prefixes: prefixes)
    }
}

// MARK: - Constructor on EventType

extension SubscriptionFilter {
    public static func onEventType(regex: String) -> Self {
        .init(type: .eventType, regex: regex)
    }

    public static func onEventType(prefixes: String...) -> Self {
        .onEventType(prefixes: prefixes)
    }

    public static func onEventType(prefixes: [String]) -> Self {
        .init(type: .eventType, prefixes: prefixes)
    }
}

// MARK: - Constructor with excludeSystemEvents

extension SubscriptionFilter {
    public static func excludeSystemEvents() -> Self {
        .onStreamName(regex: "^[^\\$].*")
    }
}
