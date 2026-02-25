//
//  KurrentDBClient+V1Projections.swift
//  swift-kurrentdb
//
//  Compatibility layer — convenience methods for projection management.
//  Prefer the target-based API: client.projections(of:), client.projection(name:)
//

import KurrentDB

@available(*, deprecated, message: "Use the target-based API instead: client.projections(of:), client.projection(name:)")
extension KurrentDBClient {
    /// Creates and executes a one-time projection that runs to completion and then stops.
    public func createOneTimeProjection(query: String) async throws(KurrentError) {
        try await projections(of: .onetime).create(query: query)
    }

    /// Creates a continuous projection that processes events in real-time as they are appended.
    public func createContinuousProjection(name: String, query: String, configure: @Sendable (Projections<SpecifiedContinuousProjectionTarget>.ContinuousCreate.Options) -> Projections<SpecifiedContinuousProjectionTarget>.ContinuousCreate.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await projections(of: .continuous(name: name)).create(query: query, options: options)
    }

    /// Creates a transient projection that runs in memory without persisting state to disk.
    public func createTransientProjection(name: String, query: String) async throws(KurrentError) {
        try await projections(of: .transient(name: name)).create(query: query)
    }

    /// Updates an existing projection's query definition.
    public func updateProjection(name: String, query: String, configure: @Sendable (Projections<NameTarget>.Update.Options) -> Projections<NameTarget>.Update.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await projections(of: NameTarget(name: name)).update(query: query, options: options)
    }

    /// Enables a projection to begin processing events from its last checkpoint position.
    public func enableProjection(name: String) async throws(KurrentError) {
        try await projections(of: NameTarget(name: name)).enable()
    }

    /// Disables a projection, pausing event processing while preserving its checkpoint.
    public func disableProjection(name: String) async throws(KurrentError) {
        try await projections(of: NameTarget(name: name)).disable()
    }

    /// Aborts a running projection immediately without writing a checkpoint.
    public func abortProjection(name: String) async throws(KurrentError) {
        try await projections(of: NameTarget(name: name)).abort()
    }

    /// Deletes a projection and optionally removes all streams it emitted.
    public func deleteProjection(name: String, configure: @Sendable (Projections<NameTarget>.Delete.Options) -> Projections<NameTarget>.Delete.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await projections(of: NameTarget(name: name)).delete(options: options)
    }

    /// Resets a projection to its initial state, clearing all state and checkpoint data.
    public func resetProjection(name: String) async throws(KurrentError) {
        try await projections(of: NameTarget(name: name)).reset()
    }

    /// Retrieves the result output of a projection, decoded to the specified Swift type.
    public func getProjectionResult<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<NameTarget>.Result.Options) -> Projections<NameTarget>.Result.Options = { $0 }) async throws(KurrentError) -> T? {
        let options = configure(.init())
        return try await projections(of: NameTarget(name: name)).result(of: T.self, options: options)
    }

    /// Retrieves the current internal state of a projection, decoded to the specified Swift type.
    public func getProjectionState<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<NameTarget>.State.Options) -> Projections<NameTarget>.State.Options = { $0 }) async throws(KurrentError) -> T? {
        let options = configure(.init())
        return try await projections(of: NameTarget(name: name)).state(of: T.self, options: options)
    }

    /// Retrieves comprehensive statistics and metadata for a specific projection.
    public func getProjectionDetail(name: String) async throws(KurrentError) -> Projection.Detail? {
        try await projections(of: NameTarget(name: name)).detail()
    }

    /// Lists all projections of a specified mode across the cluster.
    public func listAllProjections(mode: Projection.Mode) async throws(KurrentError) -> [Projection.Detail] {
        return switch mode {
        case .continuous:
            try await projections(of: UnspecifiedContinuousProjectionTarget()).list()
        case .transient:
            try await projections(of: UnspecifiedTransientProjectionTarget()).list()
        case .oneTime:
            try await projections(of: OneTimeProjectionTarget()).list()
        case .any:
            try await projections(of: AnyProjectionsTarget()).list()
        }
    }

    /// Restarts the entire projection subsystem across the cluster.
    public func restartProjectionSubsystem() async throws(KurrentError) {
        try await projections.restartSubsystem()
    }
}
