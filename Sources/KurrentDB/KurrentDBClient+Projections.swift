//
//  KurrentDBClient+Projections.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Projection Factory Methods

extension KurrentDBClient {
    /// Creates a projections interface targeting all projections.
    public var projections: Projections<AnyProjectionsTarget> {
<<<<<<< HEAD
        get{
            .init(
                target: .init(),
                selector: selector,
                callOptions: defaultCallOptions,
                eventLoopGroup: eventLoopGroup)
        }
=======
        .init(
            target: .init(),
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
>>>>>>> 6d1df011 ([REFACTOR] Split Target types into per-file Target/ folders; fix docs sample code)
    }

    /// Creates a projections interface for a specific target type.
    public func projections<Target: ProjectionsTarget>(of target: Target) -> Projections<Target> {
        .init(
            target: target,
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }

<<<<<<< HEAD
    /// Creates a projections interface for a predefined system projection.
=======
    /// Creates a projections interface for a named projection.
>>>>>>> 6d1df011 ([REFACTOR] Split Target types into per-file Target/ folders; fix docs sample code)
    public func projection(name: String) -> Projections<NameTarget> {
        .init(
            target: .init(name: name),
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface for a predefined system projection.
    public func projections(system predefined: NameTarget.Predefined) -> Projections<NameTarget> {
        .init(
            target: .init(predefined: predefined),
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }
}
<<<<<<< HEAD

// MARK: - Projection Accessors

extension KurrentDBClient {
    /// Returns a projections interface targeting all projections.
    public var anyMode: Projections<AnyProjectionsTarget> {
        projections(of: .anyMode)
    }

    /// Returns a projections interface for a continuous projection with the specified name.
    public func continuousProjection(name: String) -> Projections<SpecifiedContinuousProjectionTarget> {
        projections(of: .continuous(name: name))
    }

    /// Returns a projections interface for one-time projections.
    public var oneTimeProjection: Projections<OneTimeProjectionTarget> {
        projections(of: .onetime)
    }

    /// Returns a projections interface for a transient projection with the specified name.
    public func transientProjection(name: String) -> Projections<SpecifiedTransientProjectionTarget> {
        projections(of: .transient(name: name))
    }

    /// Returns a projections interface for a predefined system projection.
    public func systemProjection(predefined: NameTarget.Predefined) -> Projections<NameTarget> {
        projections(system: predefined)
    }
}
=======
>>>>>>> 6d1df011 ([REFACTOR] Split Target types into per-file Target/ folders; fix docs sample code)
