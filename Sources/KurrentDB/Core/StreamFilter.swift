//
//  StreamFilter.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/23.
//
import GRPCEncapsulates

/// Filter applied to a catch-up or persistent subscription to select a subset of events.
///
/// Use the static factory methods to create a filter, then chain builder methods to
/// refine the checkpoint and window behaviour.
///
/// ```swift
/// // Match streams whose name starts with "orders"
/// let filter = StreamFilter.onStreamName(prefix: "orders")
///     .checkpointIntervalMultiplier(100)
///
/// // Match events whose type matches a regex
/// let filter = StreamFilter.onEventType(regex: "^OrderPlaced$")
/// ```
public struct StreamFilter: Buildable {
    /// Controls how many filtered events trigger a checkpoint.
    public enum Window: Sendable {
        /// No upper-bound window; checkpointing is driven solely by `checkpointIntervalMultiplier`.
        case count
        /// Checkpoint after at most `max` filtered events.
        case max(UInt32)
    }

    /// Dimension on which the filter pattern is matched.
    public enum FilterType: Sendable {
        /// Filter is applied to the stream name.
        case streamName
        /// Filter is applied to the event type.
        case eventType
    }

    /// Dimension used to match incoming events.
    public internal(set) var type: FilterType
    /// Regular expression pattern, or `nil` when prefix matching is used instead.
    public internal(set) var regex: String?
    /// Checkpoint window strategy.
    public internal(set) var window: Window
    /// Prefix strings used when no regex is specified.
    public internal(set) var prefixes: [String]
    /// Number of events between server-side checkpoints.
    public internal(set) var checkpointIntervalMultiplier: UInt32

    init(type: FilterType, regex: String? = nil, window: Window = .count, prefixes: [String] = []) {
        self.type = type
        self.regex = regex
        self.window = window
        self.prefixes = prefixes
        checkpointIntervalMultiplier = .max
    }

    /// Sets the maximum number of filtered events before a checkpoint is issued.
    ///
    /// - Parameter maxCount: Maximum event count between checkpoints.
    /// - Returns: An updated copy of the filter.
    @discardableResult
    public func max(_ maxCount: UInt32) -> Self {
        withCopy { options in
            options.window = .max(maxCount)
        }
    }

    /// Sets the checkpoint interval multiplier used by the server.
    ///
    /// - Parameter multiplier: Multiplier applied to the server's base checkpoint interval.
    /// - Returns: An updated copy of the filter.
    @discardableResult
    public func checkpointIntervalMultiplier(_ multiplier: UInt32) -> Self {
        withCopy { options in
            options.checkpointIntervalMultiplier = multiplier
        }
    }

    /// Appends an additional prefix to the filter's prefix list.
    ///
    /// - Parameter prefix: Stream name or event type prefix to include.
    /// - Returns: An updated copy of the filter.
    @discardableResult
    public func add(prefix: String) -> Self {
        withCopy { options in
            options.prefixes.append(prefix)
        }
    }
}

// MARK: - Constructor on StreamName

extension StreamFilter {
    /// Creates a stream-name filter matching the given regular expression.
    ///
    /// - Parameter regex: Regular expression applied to each stream name.
    /// - Returns: A configured `StreamFilter`.
    public static func onStreamName(regex: String) -> Self {
        .init(type: .streamName, regex: regex)
    }

    /// Creates a stream-name filter matching any of the given prefixes.
    ///
    /// ```swift
    /// let filter = StreamFilter.onStreamName(prefix: "orders", "payments")
    /// ```
    ///
    /// - Parameter prefix: One or more stream name prefixes.
    /// - Returns: A configured `StreamFilter`.
    public static func onStreamName(prefix: String...) -> Self {
        .onStreamName(prefixes: prefix)
    }

    /// Creates a stream-name filter matching any of the given prefixes.
    ///
    /// - Parameter prefixes: Array of stream name prefixes.
    /// - Returns: A configured `StreamFilter`.
    public static func onStreamName(prefixes: [String]) -> Self {
        .init(type: .streamName, prefixes: prefixes)
    }
}

// MARK: - Constructor on EventType

extension StreamFilter {
    /// Creates an event-type filter matching the given regular expression.
    ///
    /// ```swift
    /// let filter = StreamFilter.onEventType(regex: "^OrderPlaced$")
    /// ```
    ///
    /// - Parameter regex: Regular expression applied to each event type name.
    /// - Returns: A configured `StreamFilter`.
    public static func onEventType(regex: String) -> Self {
        .init(type: .eventType, regex: regex)
    }

    /// Creates an event-type filter matching any of the given prefixes.
    ///
    /// - Parameter prefixes: One or more event type prefixes.
    /// - Returns: A configured `StreamFilter`.
    public static func onEventType(prefixes: String...) -> Self {
        .onEventType(prefixes: prefixes)
    }

    /// Creates an event-type filter matching any of the given prefixes.
    ///
    /// - Parameter prefixes: Array of event type prefixes.
    /// - Returns: A configured `StreamFilter`.
    public static func onEventType(prefixes: [String]) -> Self {
        .init(type: .eventType, prefixes: prefixes)
    }
}

// MARK: - Constructor with excludeSystemEvents

extension StreamFilter {
    /// Creates a stream-name filter that excludes all system streams (names starting with `$`).
    ///
    /// - Returns: A `StreamFilter` configured to skip system streams.
    public static func excludeSystemEvents() -> Self {
        .onStreamName(regex: "^[^\\$].*")
    }
}

// MARK: - Deprecated alias

@available(*, deprecated, renamed: "StreamFilter")
public typealias SubscriptionFilter = StreamFilter
