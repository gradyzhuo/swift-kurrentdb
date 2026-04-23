//
//  KurrentDBClient+Projections.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Projection Factory Methods

extension KurrentDBClient {
    /// Returns a ``Projections`` service scoped to the given target.
    ///
    /// - Parameter target: The projection target, such as `.continuous(name:)`, `.transient(name:)`, or `.onetime`.
    /// - Returns: A ``Projections`` instance configured for the specified target.
    public func projections<Target: ProjectionsTarget>(of target: Target) -> Projections<Target> {
        .init(
            target: target,
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }

    /// Returns a ``Projections`` service scoped to the named projection.
    ///
    /// ```swift
    /// try await client.projections(name: "my-projection").enable()
    /// let state = try await client.projections(name: "my-projection").state(of: MyState.self)
    /// ```
    ///
    /// - Parameter name: Name of the projection to manage or query.
    /// - Returns: A ``Projections`` instance targeting the named projection.
    public func projections(name: String) -> Projections<NameTarget> {
        .init(
            target: .init(name: name),
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }

    /// Returns a ``Projections`` service scoped to a built-in system projection.
    ///
    /// ```swift
    /// try await client.projections(system: .byCategory).enable()
    /// ```
    ///
    /// - Parameter predefined: The system projection to target, such as `.byCategory` or `.byEventType`.
    /// - Returns: A ``Projections`` instance targeting the specified system projection.
    public func projections(system predefined: NameTarget.Predefined) -> Projections<NameTarget> {
        .init(
            target: .init(predefined: predefined),
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }
}
