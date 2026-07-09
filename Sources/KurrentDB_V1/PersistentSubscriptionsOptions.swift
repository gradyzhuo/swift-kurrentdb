//
//  PersistentSubscriptionsOptions.swift
//  swift-kurrentdb
//
//  V1 compatibility options for persistent subscription operations.
//  These types provide the builder-pattern (method-chaining) API and are
//  converted to the target-based API Options via internal bridge initializers.
//

import Foundation
import KurrentDB

// MARK: - PersistentSubscriptionsCreateOptions

/// V1 options for creating a persistent subscription on a specific stream.
public struct PersistentSubscriptionsCreateOptions: Sendable {
    public var settings: PersistentSubscription.CreateSettings
    public var revision: RevisionCursor

    public init() {
        settings = .init()
        revision = .end
    }

    @discardableResult
    public func startFrom(revision: RevisionCursor) -> Self {
        var copy = self
        copy.revision = revision
        return copy
    }
}

extension PersistentSubscriptions.SpecifiedStream.Create.Options {
    init(from options: PersistentSubscriptionsCreateOptions) {
        self.init()
        self.settings = options.settings
        self.revision = options.revision
    }
}

// MARK: - PersistentSubscriptionsUpdateOptions

/// V1 options for updating a persistent subscription on a specific stream.
public struct PersistentSubscriptionsUpdateOptions: Sendable {
    public var settings: PersistentSubscription.UpdateSettings
    public var revision: RevisionCursor?

    public init() {
        settings = .init()
        revision = nil
    }

    @discardableResult
    public func startFrom(revision: RevisionCursor) -> Self {
        var copy = self
        copy.revision = revision
        return copy
    }
}

extension PersistentSubscriptions.SpecifiedStream.Update.Options {
    init(from options: PersistentSubscriptionsUpdateOptions) {
        self.init()
        self.settings = options.settings
        self.revision = options.revision
    }
}

// MARK: - PersistentSubscriptionsReplayParkedOptions

/// V1 options for replaying parked messages on a specific stream.
public struct PersistentSubscriptionsReplayParkedOptions: Sendable {
    public enum StopAtOption: Sendable {
        case position(position: Int64)
        case noLimit
    }

    public var stopAt: StopAtOption

    public init() {
        stopAt = .noLimit
    }

    @discardableResult
    public func stopAt(_ stopAt: StopAtOption) -> Self {
        var copy = self
        copy.stopAt = stopAt
        return copy
    }
}

extension PersistentSubscriptions.SpecifiedStream.ReplayParked.Options {
    init(from options: PersistentSubscriptionsReplayParkedOptions) {
        self.init()
        switch options.stopAt {
        case .noLimit:
            self.stopAt = .noLimit
        case let .position(position):
            self.stopAt = .position(position: position)
        }
    }
}

// MARK: - PersistentSubscriptionsReadOptions

/// V1 options for subscribing to a persistent subscription on a specific stream.
public struct PersistentSubscriptionsReadOptions: Sendable {
    public var bufferSize: Int32
    public var uuidOption: UUID.Option

    public init() {
        bufferSize = 1000
        uuidOption = .string
    }

    @discardableResult
    public func bufferSize(_ bufferSize: Int32) -> Self {
        var copy = self
        copy.bufferSize = bufferSize
        return copy
    }

    @discardableResult
    public func uuidOption(_ uuidOption: UUID.Option) -> Self {
        var copy = self
        copy.uuidOption = uuidOption
        return copy
    }
}

extension PersistentSubscriptions.SpecifiedStream.Read.Options {
    init(from options: PersistentSubscriptionsReadOptions) {
        self.init()
        self.bufferSize = options.bufferSize
        self.uuidOption = options.uuidOption
    }
}

// MARK: - PersistentSubscriptionsAllStreamCreateOptions

/// V1 options for creating a persistent subscription to all streams.
public struct PersistentSubscriptionsAllStreamCreateOptions: Sendable {
    public var settings: PersistentSubscription.CreateSettings
    public var filter: StreamFilter?
    public var position: PositionCursor

    public init() {
        settings = .init()
        filter = nil
        position = .end
    }

    @discardableResult
    public func filter(_ filter: StreamFilter) -> Self {
        var copy = self
        copy.filter = filter
        return copy
    }

    @discardableResult
    public func startFrom(position: PositionCursor) -> Self {
        var copy = self
        copy.position = position
        return copy
    }
}

extension PersistentSubscriptions.AllStream.Create.Options {
    init(from options: PersistentSubscriptionsAllStreamCreateOptions) {
        self.init()
        self.settings = options.settings
        self.filter = options.filter
        self.position = options.position
    }
}

// MARK: - PersistentSubscriptionsAllStreamUpdateOptions

/// V1 options for updating a persistent subscription to all streams.
public struct PersistentSubscriptionsAllStreamUpdateOptions: Sendable {
    public var settings: PersistentSubscription.UpdateSettings
    public var position: PositionCursor?

    public init() {
        settings = .init()
        position = nil
    }

    @discardableResult
    public func startFrom(position: PositionCursor) -> Self {
        var copy = self
        copy.position = position
        return copy
    }
}

extension PersistentSubscriptions.AllStream.Update.Options {
    init(from options: PersistentSubscriptionsAllStreamUpdateOptions) {
        self.init()
        self.settings = options.settings
        self.position = options.position
    }
}

// MARK: - PersistentSubscriptionsAllStreamReplayParkedOptions

/// V1 options for replaying parked messages on all streams.
public struct PersistentSubscriptionsAllStreamReplayParkedOptions: Sendable {
    public enum StopAtOption: Sendable {
        case position(position: Int64)
        case noLimit
    }

    public var stopAt: StopAtOption

    public init() {
        stopAt = .noLimit
    }

    @discardableResult
    public func stopAt(_ stopAt: StopAtOption) -> Self {
        var copy = self
        copy.stopAt = stopAt
        return copy
    }
}

extension PersistentSubscriptions.AllStream.ReplayParked.Options {
    init(from options: PersistentSubscriptionsAllStreamReplayParkedOptions) {
        self.init()
        switch options.stopAt {
        case .noLimit:
            self.stopAt = .noLimit
        case let .position(position):
            self.stopAt = .position(position: position)
        }
    }
}

// MARK: - PersistentSubscriptionsAllStreamReadOptions

/// V1 options for subscribing to a persistent subscription on all streams.
public struct PersistentSubscriptionsAllStreamReadOptions: Sendable {
    public var bufferSize: Int32
    public var uuidOption: UUID.Option

    public init() {
        bufferSize = 1000
        uuidOption = .string
    }

    @discardableResult
    public func bufferSize(_ bufferSize: Int32) -> Self {
        var copy = self
        copy.bufferSize = bufferSize
        return copy
    }

    @discardableResult
    public func uuidOption(_ uuidOption: UUID.Option) -> Self {
        var copy = self
        copy.uuidOption = uuidOption
        return copy
    }
}

extension PersistentSubscriptions.AllStream.Read.Options {
    init(from options: PersistentSubscriptionsAllStreamReadOptions) {
        self.init()
        self.bufferSize = options.bufferSize
        self.uuidOption = options.uuidOption
    }
}
