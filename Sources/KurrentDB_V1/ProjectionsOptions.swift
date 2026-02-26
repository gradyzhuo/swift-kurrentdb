//
//  ProjectionsOptions.swift
//  swift-kurrentdb
//
//  V1 compatibility options for projection operations.
//  These types provide the builder-pattern (method-chaining) API and are
//  converted to the target-based API Options via internal bridge initializers.
//

import KurrentDB

// MARK: - ProjectionsContinuousCreateOptions

/// V1 options for creating a continuous projection.
public struct ProjectionsContinuousCreateOptions: Sendable {
    public var emitEnabled: Bool
    public var trackEmittedStreams: Bool

    public init(emitEnabled: Bool = true, trackEmittedStreams: Bool = true) {
        self.emitEnabled = emitEnabled
        self.trackEmittedStreams = trackEmittedStreams
    }

    @discardableResult
    public func emit(enabled: Bool) -> Self {
        var copy = self
        copy.emitEnabled = enabled
        return copy
    }

    @discardableResult
    public func trackEmittedStreams(_ value: Bool) -> Self {
        var copy = self
        copy.trackEmittedStreams = value
        return copy
    }
}

extension Projections.ContinuousCreate.Options {
    init(from options: ProjectionsContinuousCreateOptions) {
        self.init(emitEnabled: options.emitEnabled, trackEmittedStreams: options.trackEmittedStreams)
    }
}

// MARK: - ProjectionsUpdateOptions

/// V1 options for updating a projection.
public struct ProjectionsUpdateOptions: Sendable {
    public enum EmitOption: Sendable {
        case noEmit
        case enable(Bool)
    }

    public var emitOption: EmitOption

    public init() {
        emitOption = .noEmit
    }

    @discardableResult
    public func noEmit() -> Self {
        var copy = self
        copy.emitOption = .noEmit
        return copy
    }

    @discardableResult
    public func emit(enabled: Bool) -> Self {
        var copy = self
        copy.emitOption = .enable(enabled)
        return copy
    }
}

extension Projections.Update.Options {
    init(from options: ProjectionsUpdateOptions) {
        self.init()
        switch options.emitOption {
        case .noEmit:
            self.emitOption = .noEmit
        case let .enable(enabled):
            self.emitOption = .enable(enabled)
        }
    }
}

// MARK: - ProjectionsDeleteOptions

/// V1 options for deleting a projection.
public struct ProjectionsDeleteOptions: Sendable {
    public var deleteCheckpointStream: Bool
    public var deleteEmittedStreams: Bool
    public var deleteStateStream: Bool

    public init() {
        deleteCheckpointStream = false
        deleteEmittedStreams = false
        deleteStateStream = false
    }

    @discardableResult
    public func deleteCheckpointStream(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.deleteCheckpointStream = enabled
        return copy
    }

    @discardableResult
    public func deleteEmittedStreams(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.deleteEmittedStreams = enabled
        return copy
    }

    @discardableResult
    public func deleteStateStream(_ enabled: Bool = true) -> Self {
        var copy = self
        copy.deleteStateStream = enabled
        return copy
    }
}

extension Projections.Delete.Options {
    init(from options: ProjectionsDeleteOptions) {
        self.init()
        self.deleteCheckpointStream = options.deleteCheckpointStream
        self.deleteEmittedStreams = options.deleteEmittedStreams
        self.deleteStateStream = options.deleteStateStream
    }
}

// MARK: - ProjectionsResultOptions

/// V1 options for retrieving a projection result.
public struct ProjectionsResultOptions: Sendable {
    public var partition: String?

    public init() {
        partition = nil
    }

    @discardableResult
    public func partition(_ partition: String) -> Self {
        var copy = self
        copy.partition = partition
        return copy
    }
}

extension Projections.Result.Options {
    init(from options: ProjectionsResultOptions) {
        self.init()
        self.partition = options.partition
    }
}

// MARK: - ProjectionsStateOptions

/// V1 options for retrieving a projection state.
public struct ProjectionsStateOptions: Sendable {
    public var partition: String?

    public init() {
        partition = nil
    }

    @discardableResult
    public func partition(_ partition: String) -> Self {
        var copy = self
        copy.partition = partition
        return copy
    }
}

extension Projections.State.Options {
    init(from options: ProjectionsStateOptions) {
        self.init()
        self.partition = options.partition
    }
}
