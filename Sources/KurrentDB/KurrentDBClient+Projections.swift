//
//  KurrentDBClient+Projections.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides methods for projection operations.
extension KurrentDBClient {
    /// Creates a continuous projection with a specified name and query.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to create.
    ///   - query: The query defining the projection's logic.
    ///   - configure: A closure to customize the creation options, defaulting to no modifications.
    /// - Throws: An error if the creation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func createContinuousProjection(name: String, query: String, configure: @Sendable (Projections<String>.ContinuousCreate.Options) -> Projections<String>.ContinuousCreate.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).createContinuous(query: query, options: options)
    }
    
    /// Updates an existing projection with a new query.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to update.
    ///   - query: The updated query for the projection.
    ///   - configure: A closure to customize the update options, defaulting to no modifications.
    /// - Throws: An error if the update fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func updateProjection(name: String, query: String, configure: @Sendable (Projections<String>.Update.Options) -> Projections<String>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).update(query: query, options: options)
    }
    
    /// Enables a projection.
    ///
    /// - Parameter name: The name of the projection to enable.
    /// - Throws: An error if the enable operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func enableProjection(name: String) async throws {
        try await projections(name: name).enable()
    }
    
    /// Disables a projection.
    ///
    /// - Parameter name: The name of the projection to disable.
    /// - Throws: An error if the disable operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func disableProjection(name: String) async throws {
        try await projections(name: name).disable()
    }
    
    /// Aborts a projection.
    ///
    /// - Parameter name: The name of the projection to abort.
    /// - Throws: An error if the abort operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func abortProjection(name: String) async throws {
        try await projections(name: name).abort()
    }
    
    /// Deletes a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to delete.
    ///   - configure: A closure to customize the delete options, defaulting to no modifications.
    /// - Throws: An error if the delete operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func deleteProjection(name: String, configure: @Sendable (Projections<String>.Delete.Options) -> Projections<String>.Delete.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).delete(options: options)
    }
    
    /// Resets a projection to its initial state.
    ///
    /// - Parameter name: The name of the projection to reset.
    /// - Throws: An error if the reset operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func resetProjection(name: String) async throws {
        try await projections(name: name).reset()
    }

    /// Retrieves the result of a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - configure: A closure to customize the result options, defaulting to no modifications.
    /// - Returns: The decoded result of type `T`, or `nil` if no result is available.
    /// - Throws: An error if the retrieval or decoding fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func getProjectionResult<T: Decodable & Sendable>(of: T.Type = T.self, name: String, configure: @Sendable (Projections<String>.Result.Options) -> Projections<String>.Result.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).result(of: T.self, options: options)
    }
    
    /// Retrieves the state of a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - configure: A closure to customize the state options, defaulting to no modifications.
    /// - Returns: The decoded state of type `T`, or `nil` if no state is available.
    /// - Throws: An error if the retrieval or decoding fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func getProjectionState<T: Decodable & Sendable>(of: T.Type = T.self, name: String, configure: @Sendable (Projections<String>.State.Options) -> Projections<String>.State.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).state(of: T.self, options: options)
    }
    
    /// Retrieves detailed statistics for a projection.
    ///
    /// - Parameter name: The name of the projection.
    /// - Returns: A `Projections<String>.Statistics.Detail` object if available, otherwise `nil`.
    /// - Throws: An error if the retrieval fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func getProjectionDetail(name: String) async throws -> Projections<String>.Statistics.Detail? {
        return try await projections(name: name).detail()
    }
    

    public func listAllProjections() async throws -> [Projections<AllProjectionTarget<AnyMode>>.Statistics.Detail] {
        try await projections(all: .any ).list()
    }
    
    /// Restarts the projection subsystem.
    ///
    /// - Throws: A `KurrentError` if the restart operation fails.
    /// - Note: This method must be called with `await` in an asynchronous context due to the `actor` model.
    public func restartProjectionSubsystem() async throws(KurrentError) {
        let usecase = Projections<AllProjectionTarget<AnyMode>>.RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: defaultCallOptions)
    }
}
