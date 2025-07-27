//
//  KurrentDBClient+Projections.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

/// Provides methods for projection operations.
extension KurrentDBClient {
    public func createContinuousProjection(name: String, query: String, configure: @Sendable (Projections<String>.ContinuousCreate.Options) -> Projections<String>.ContinuousCreate.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).createContinuous(query: query, options: options)
    }

    public func updateProjection(name: String, query: String, configure: @Sendable (Projections<String>.Update.Options) -> Projections<String>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).update(query: query, options: options)
    }

    public func enableProjection(name: String) async throws {
        try await projections(name: name).enable()
    }

    public func disableProjection(name: String) async throws {
        try await projections(name: name).disable()
    }

    public func abortProjection(name: String) async throws {
        try await projections(name: name).abort()
    }

    public func deleteProjection(name: String, configure: @Sendable (Projections<String>.Delete.Options) -> Projections<String>.Delete.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).delete(options: options)
    }

    public func resetProjection(name: String) async throws {
        try await projections(name: name).reset()
    }

    public func getProjectionResult<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<String>.Result.Options) -> Projections<String>.Result.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).result(of: T.self, options: options)
    }

    public func getProjectionState<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<String>.State.Options) -> Projections<String>.State.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).state(of: T.self, options: options)
    }

    public func getProjectionDetail(name: String) async throws -> Projections<String>.Statistics.Detail? {
        try await projections(name: name).detail()
    }

    public func listAllProjections() async throws -> [Projections<AllProjectionTarget<AnyMode>>.Statistics.Detail] {
        try await projections(all: .any).list()
    }

    public func restartProjectionSubsystem() async throws(KurrentError) {
        let usecase = Projections<AllProjectionTarget<AnyMode>>.RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: defaultCallOptions)
    }
}
