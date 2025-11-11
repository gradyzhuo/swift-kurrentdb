//
//  KurrentDBClient+Projections.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides methods for projection operations.
extension KurrentDBClient {
    /// Creates a continuous projection that listens to specified streams and processes new events, potentially linking them back to streams for event collection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - query: The query string for the projection.
    ///   - configure: A closure to configure the creation options.
    /// - Throws: An error if the projection creation fails.
    public func createContinuousProjection(name: String, query: String, configure: @Sendable (Projections<String>.ContinuousCreate.Options) -> Projections<String>.ContinuousCreate.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).createContinuous(query: query, options: options)
    }

    /// Updates an existing projection with a new query and options.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - query: The updated query string for the projection.
    ///   - configure: A closure to configure the update options.
    /// - Throws: An error if the projection update fails.
    public func updateProjection(name: String, query: String, configure: @Sendable (Projections<String>.Update.Options) -> Projections<String>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).update(query: query, options: options)
    }

    /// Enables a projection, allowing it to start processing events.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if enabling the projection fails.
    public func enableProjection(name: String) async throws {
        try await projections(name: name).enable()
    }

    /// Disables a projection, stopping it from processing events.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if disabling the projection fails.
    public func disableProjection(name: String) async throws {
        try await projections(name: name).disable()
    }

    /// Aborts a running projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if aborting the projection fails.
    public func abortProjection(name: String) async throws {
        try await projections(name: name).abort()
    }

    /// Deletes a projection with optional configuration.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - configure: A closure to configure the deletion options.
    /// - Throws: An error if the projection deletion fails.
    public func deleteProjection(name: String, configure: @Sendable (Projections<String>.Delete.Options) -> Projections<String>.Delete.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).delete(options: options)
    }

    /// Resets a projection to its initial state.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if resetting the projection fails.
    public func resetProjection(name: String) async throws {
        try await projections(name: name).reset()
    }

    /// Retrieves the result of a projection.
    ///
    /// - Parameters:
    ///   - of: The type of the result to decode.
    ///   - name: The name of the projection.
    ///   - configure: A closure to configure the result retrieval options.
    /// - Returns: The decoded result, or nil if not available.
    /// - Throws: An error if retrieving the result fails.
    public func getProjectionResult<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<String>.Result.Options) -> Projections<String>.Result.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).result(of: T.self, options: options)
    }

    /// Retrieves the state of a projection.
    ///
    /// - Parameters:
    ///   - of: The type of the state to decode.
    ///   - name: The name of the projection.
    ///   - configure: A closure to configure the state retrieval options.
    /// - Returns: The decoded state, or nil if not available.
    /// - Throws: An error if retrieving the state fails.
    public func getProjectionState<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<String>.State.Options) -> Projections<String>.State.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).state(of: T.self, options: options)
    }

    /// Retrieves detailed statistics for a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Returns: The detailed statistics, or nil if not available.
    /// - Throws: An error if retrieving the detail fails.
    public func getProjectionDetail(name: String) async throws -> Projections<String>.Statistics.Detail? {
        try await projections(name: name).detail()
    }

    /// Lists all projections across all targets and modes.
    ///
    /// - Returns: An array of detailed statistics for all projections.
    /// - Throws: An error if listing fails.
    public func listAllProjections() async throws -> [Projections<AllProjectionTarget<AnyMode>>.Statistics.Detail] {
        try await projections(all: .any).list()
    }

    /// Restarts the projection subsystem.
    ///
    /// - Throws: An error if restarting fails.
    public func restartProjectionSubsystem() async throws(KurrentError) {
        let usecase = Projections<AllProjectionTarget<AnyMode>>.RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: defaultCallOptions)
    }
}
