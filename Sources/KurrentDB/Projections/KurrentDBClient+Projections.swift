//
//  KurrentDBClient+Projections.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Projection Factory Methods

extension KurrentDBClient {
    /// Creates a projections interface for a specific target type.
    ///
    /// - Parameter target: The projection target (e.g., `.continuous(name:)`, `.transient(name:)`, `.onetime`).
    /// - Returns: A configured ``Projections`` instance.
    public func projections<Target: ProjectionsTarget>(of target: Target) -> Projections<Target> {
        .init(
            target: target,
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface for a named projection.
    ///
    /// Use this to manage (enable, disable, update, delete, reset) or query (state, result, detail)
    /// an existing projection by name.
    ///
    /// ```swift
    /// try await client.projections(name: "my-projection").enable()
    /// let state = try await client.projections(name: "my-projection").state(of: MyState.self)
    /// ```
    ///
    /// - Parameter name: The projection name.
    public func projections(name: String) -> Projections<NameTarget> {
        .init(
            target: .init(name: name),
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface for a predefined system projection.
    ///
    /// ```swift
    /// try await client.projections(system: .byCategory).enable()
    /// ```
    ///
    /// - Parameter predefined: The system projection (e.g., `.byCategory`, `.byEventType`, `.byCorrelationId`).
    public func projections(system predefined: NameTarget.Predefined) -> Projections<NameTarget> {
        .init(
            target: .init(predefined: predefined),
            selector: selector,
            callOptions: defaultCallOptions,
            eventLoopGroup: eventLoopGroup)
    }
}
