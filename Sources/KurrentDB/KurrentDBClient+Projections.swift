//
//  KurrentDBClient+Projections.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//
//MARK: KurrentDBClient + projections
extension KurrentDBClient {
    /// Creates a projections interface for the given projection mode across every projection.
    ///
    /// - Parameter mode: The desired projection mode (continuous, transient, etc.).
    package func projections() -> Projections<AnyProjectionTarget> {
        .init(target: .init(), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
    
    /// Creates a projections interface for the given projection mode across every projection.
    ///
    /// - Parameter mode: The desired projection mode (continuous, transient, etc.).
    package func projections<Target: ProjectionTarget>(of target: Target) -> Projections<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface aimed at a predefined system projection.
    ///
    /// - Parameter predefined: The predefined system projection target, such as `$by_category`.
    package func projections(system predefined: NameTarget.Predefined) -> Projections<NameTarget> {
        .init(target: .init(predefined: predefined), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}


extension KurrentDBClient {
    var anyProjection: Projections<AnyProjectionTarget>{
        get{
            return projections(of: .any)
        }
    }
    
    func continuousProjection(name: String)-> Projections<ContinuousTarget>{
        return projections(of: .continuous(name: name))
    }
    
    var oneTimeProjection: Projections<OneTimeTarget>{
        return projections(of: .onetime)
    }
    
    func transientProjection(name: String) ->  Projections<TransientTarget>{
        return projections(of: .transient(name: name))
    }
    
    func systemProjection(predefined: NameTarget.Predefined) -> Projections<NameTarget>{
        return projections(system: predefined)
    }
    
}

/// Provides methods for projection operations.
extension KurrentDBClient {
    /// Creates a one-time projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - query: The query string for the projection.
    ///   - configure: A closure to configure the creation options.
    /// - Throws: An error if the projection creation fails.
    public func createOneTimeProjection(query: String) async throws {
        try await projections(of: .onetime).create(query: query)
    }
    
    /// Creates a continuous projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - query: The query string for the projection.
    ///   - configure: A closure to configure the creation options.
    /// - Throws: An error if the projection creation fails.
    public func createContinuousProjection(name: String, query: String, configure: @Sendable (Projections<ContinuousTarget>.ContinuousCreate.Options) -> Projections<ContinuousTarget>.ContinuousCreate.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(of: .continuous(name: name)).create(query: query, options: options)
    }
    
    /// Creates a transient projection.
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - query: The updated query string for the projection.
    /// - Throws: An error if the projection update fails.
    public func createTransientProjection(name: String, query: String) async throws {
        try await projections(of: .transient(name: name)).create(query: query)
    }

    /// Updates an existing projection with a new query and options.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - query: The updated query string for the projection.
    ///   - configure: A closure to configure the update options.
    /// - Throws: An error if the projection update fails.
    public func updateProjection(name: String, query: String, configure: @Sendable (Projections<NameTarget>.Update.Options) -> Projections<NameTarget>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(of: NameTarget(name: name)).update(query: query, options: options)
    }

    /// Enables a projection, allowing it to start processing events.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if enabling the projection fails.
    public func enableProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).enable()
    }

    /// Disables a projection, stopping it from processing events.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if disabling the projection fails.
    public func disableProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).disable()
    }

    /// Aborts a running projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if aborting the projection fails.
    public func abortProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).abort()
    }

    /// Deletes a projection with optional configuration.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - configure: A closure to configure the deletion options.
    /// - Throws: An error if the projection deletion fails.
    public func deleteProjection(name: String, configure: @Sendable (Projections<NameTarget>.Delete.Options) -> Projections<NameTarget>.Delete.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(of: NameTarget(name: name)).delete(options: options)
    }

    /// Resets a projection to its initial state.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Throws: An error if resetting the projection fails.
    public func resetProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).reset()
    }

    /// Retrieves the result of a projection.
    ///
    /// - Parameters:
    ///   - of: The type of the result to decode.
    ///   - name: The name of the projection.
    ///   - configure: A closure to configure the result retrieval options.
    /// - Returns: The decoded result, or nil if not available.
    /// - Throws: An error if retrieving the result fails.
    public func getProjectionResult<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<NameTarget>.Result.Options) -> Projections<NameTarget>.Result.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(of: NameTarget(name: name)).result(of: T.self, options: options)
    }

    /// Retrieves the state of a projection.
    ///
    /// - Parameters:
    ///   - of: The type of the state to decode.
    ///   - name: The name of the projection.
    ///   - configure: A closure to configure the state retrieval options.
    /// - Returns: The decoded state, or nil if not available.
    /// - Throws: An error if retrieving the state fails.
    public func getProjectionState<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<NameTarget>.State.Options) -> Projections<NameTarget>.State.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(of: NameTarget(name: name)).state(of: T.self, options: options)
    }

    /// Retrieves detailed statistics for a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    /// - Returns: The detailed statistics, or nil if not available.
    /// - Throws: An error if retrieving the detail fails.
    public func getProjectionDetail(name: String) async throws -> Projections<NameTarget>.Statistics.Detail? {
        try await projections(of: NameTarget(name: name)).detail()
    }

    /// Lists all projections across all targets and modes.
    ///
    /// - Returns: An array of detailed statistics for all projections.
    /// - Throws: An error if listing fails.
    public func listAllProjections<Mode: ProjectionMode>(mode: Mode) async throws -> [Projections<AnyProjectionTarget>.Statistics.Detail] {
        try await projections().list(for: mode)
    }

    /// Restarts the projection subsystem.
    ///
    /// - Throws: An error if restarting fails.
    public func restartProjectionSubsystem() async throws(KurrentError) {
        let usecase = Projections<AnyProjectionTarget>.RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: defaultCallOptions)
    }
}
