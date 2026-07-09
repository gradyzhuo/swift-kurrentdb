//
//  StreamsOptions.swift
//  swift-kurrentdb
//
//  V1 compatibility options for stream operations.
//  These types provide the builder-pattern (method-chaining) API and are
//  converted to the target-based API Options via internal bridge initializers.
//

import KurrentDB

// MARK: - StreamsAppendOptions

/// V1 options for appending events to a stream.
public struct StreamsAppendOptions: Sendable {
    public var expectedRevision: StreamRevision

    public init() {
        expectedRevision = .any
    }

    @discardableResult
    public func revision(expected: StreamRevision) -> Self {
        var copy = self
        copy.expectedRevision = expected
        return copy
    }
}

extension Streams.Append.Options {
    init(from options: StreamsAppendOptions) {
        self.init()
        self.expectedRevision = options.expectedRevision
    }
}

// MARK: - StreamsReadOptions

/// V1 options for reading events from a stream.
public struct StreamsReadOptions: Sendable {
    public var revision: RevisionCursor
    public var direction: Direction
    public var resolveLinks: Bool
    public var limit: UInt64
    public var uuidOption: UUIDOption
    public var compatibility: UInt32

    public init() {
        resolveLinks = false
        limit = .max
        uuidOption = .string
        compatibility = 0
        revision = .start
        direction = .forward
    }

    @discardableResult
    public func resolveLinks(_ value: Bool = true) -> Self {
        var copy = self
        copy.resolveLinks = value
        return copy
    }

    @discardableResult
    public func limit(_ limit: UInt64) -> Self {
        var copy = self
        copy.limit = limit
        return copy
    }

    @discardableResult
    public func uuidOption(_ uuidOption: UUIDOption) -> Self {
        var copy = self
        copy.uuidOption = uuidOption
        return copy
    }

    @discardableResult
    public func compatibility(_ compatibility: UInt32) -> Self {
        var copy = self
        copy.compatibility = compatibility
        return copy
    }

    @discardableResult
    public func forward() -> Self {
        var copy = self
        copy.direction = .forward
        return copy
    }

    @discardableResult
    public func backward() -> Self {
        var copy = self
        copy.direction = .backward
        return copy
    }

    @discardableResult
    public func startFrom(revision: RevisionCursor) -> Self {
        var copy = self
        copy.revision = revision
        switch revision {
        case .start:
            copy.direction = .forward
        case .end:
            copy.direction = .backward
        case .specified:
            break
        }
        return copy
    }

    @discardableResult
    public func revision(from revision: UInt64) -> Self {
        var copy = self
        copy.revision = .specified(revision)
        return copy
    }
}

extension Streams.Read.Options {
    init(from options: StreamsReadOptions) {
        self.init()
        self.revision = options.revision
        self.direction = options.direction
        self.resolveLinks = options.resolveLinks
        self.limit = options.limit
        self.uuidOption = options.uuidOption
        self.compatibility = options.compatibility
    }
}

// MARK: - StreamsSubscribeOptions

/// V1 options for subscribing to a stream.
public struct StreamsSubscribeOptions: Sendable {
    public var resolveLinksEnabled: Bool
    public var uuidOption: UUIDOption
    public var revision: RevisionCursor

    public init() {
        resolveLinksEnabled = false
        uuidOption = .string
        revision = .end
    }

    @discardableResult
    public func resolveLinks() -> Self {
        var copy = self
        copy.resolveLinksEnabled = true
        return copy
    }

    @discardableResult
    public func uuidOption(_ uuidOption: UUIDOption) -> Self {
        var copy = self
        copy.uuidOption = uuidOption
        return copy
    }

    @discardableResult
    public func startFrom(revision: RevisionCursor) -> Self {
        var copy = self
        copy.revision = revision
        return copy
    }
}

extension Streams.Subscribe.Options {
    init(from options: StreamsSubscribeOptions) {
        self.init()
        self.resolveLinksEnabled = options.resolveLinksEnabled
        self.uuidOption = options.uuidOption
        self.revision = options.revision
    }
}

// MARK: - StreamsDeleteOptions

/// V1 options for deleting a stream.
public struct StreamsDeleteOptions: Sendable {
    public var expectedRevision: StreamRevision

    public init() {
        expectedRevision = .streamExists
    }

    @discardableResult
    public func revision(expected: StreamRevision) -> Self {
        var copy = self
        copy.expectedRevision = expected
        return copy
    }
}

extension Streams.Delete.Options {
    init(from options: StreamsDeleteOptions) {
        self.init()
        self.expectedRevision = options.expectedRevision
    }
}

// MARK: - StreamsTombstoneOptions

/// V1 options for tombstoning (hard-deleting) a stream.
public struct StreamsTombstoneOptions: Sendable {
    public var expectedRevision: StreamRevision

    public init() {
        expectedRevision = .streamExists
    }

    @discardableResult
    public func revision(expected: StreamRevision) -> Self {
        var copy = self
        copy.expectedRevision = expected
        return copy
    }
}

extension Streams.Tombstone.Options {
    init(from options: StreamsTombstoneOptions) {
        self.init(expectedRevision: options.expectedRevision)
    }
}

// MARK: - StreamsReadAllOptions

/// V1 options for reading all streams.
public struct StreamsReadAllOptions: Sendable {
    public var position: PositionCursor
    public var direction: Direction
    public var resolveLinksEnabled: Bool
    public var limit: UInt64
    public var uuidOption: UUIDOption
    public var compatibility: UInt32

    public init() {
        resolveLinksEnabled = false
        limit = .max
        uuidOption = .string
        compatibility = 0
        position = .start
        direction = .forward
    }

    @discardableResult
    public func resolveLinks() -> Self {
        var copy = self
        copy.resolveLinksEnabled = true
        return copy
    }

    @discardableResult
    public func limit(_ limit: UInt64) -> Self {
        var copy = self
        copy.limit = limit
        return copy
    }

    @discardableResult
    public func uuidOption(_ uuidOption: UUIDOption) -> Self {
        var copy = self
        copy.uuidOption = uuidOption
        return copy
    }

    @discardableResult
    public func compatibility(_ compatibility: UInt32) -> Self {
        var copy = self
        copy.compatibility = compatibility
        return copy
    }

    @discardableResult
    public func forward() -> Self {
        var copy = self
        copy.direction = .forward
        return copy
    }

    @discardableResult
    public func backward() -> Self {
        var copy = self
        copy.direction = .backward
        return copy
    }

    @discardableResult
    public func startFrom(position: PositionCursor) -> Self {
        var copy = self
        copy.position = position
        return copy
    }
}

extension Streams.ReadAll.Options {
    init(from options: StreamsReadAllOptions) {
        self.init()
        self.position = options.position
        self.direction = options.direction
        self.resolveLinksEnabled = options.resolveLinksEnabled
        self.limit = options.limit
        self.uuidOption = options.uuidOption
        self.compatibility = options.compatibility
    }
}

// MARK: - StreamsSubscribeAllOptions

/// V1 options for subscribing to all streams.
public struct StreamsSubscribeAllOptions: Sendable {
    public var position: PositionCursor
    public var resolveLinksEnabled: Bool
    public var uuidOption: UUIDOption
    public var filter: StreamFilter?

    public init() {
        resolveLinksEnabled = false
        uuidOption = .string
        filter = nil
        position = .end
    }

    @discardableResult
    public func resolveLinks() -> Self {
        var copy = self
        copy.resolveLinksEnabled = true
        return copy
    }

    @discardableResult
    public func filter(_ filter: StreamFilter) -> Self {
        var copy = self
        copy.filter = filter
        return copy
    }

    @discardableResult
    public func uuidOption(_ uuidOption: UUIDOption) -> Self {
        var copy = self
        copy.uuidOption = uuidOption
        return copy
    }

    @discardableResult
    public func startFrom(position: PositionCursor) -> Self {
        var copy = self
        copy.position = position
        return copy
    }
}

extension Streams.SubscribeAll.Options {
    init(from options: StreamsSubscribeAllOptions) {
        self.init()
        self.position = options.position
        self.resolveLinksEnabled = options.resolveLinksEnabled
        self.uuidOption = options.uuidOption
        self.filter = options.filter
    }
}
