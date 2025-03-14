//
//  Projections+Convenience.swift
//  kurrentdb-swift
//
//  Created by Grady Zhuo on 2025/3/13.
//

extension Projections where Target == ContinuousProjectionTarget {
    public func create(query: String, configure: (ContinuousCreate.Options) throws ->ContinuousCreate.Options) async throws {
        let options = try configure(.init())
        let usecase = ContinuousCreate(name: name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func delete(configure: (Delete.Options) throws ->Delete.Options) async throws {
        let options = try configure(.init())
        let usecase = Delete(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func update(query: String?, configure: (Update.Options) throws ->Update.Options) async throws {
        let options = try configure(.init(emitOption: .noEmit))
        let usecase = Update(name: name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func disable(configure: (Disable.Options) throws ->Disable.Options) async throws {
        let options = try configure(.init(writeCheckpoint: false))
        let usecase = Disable(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func reset(configure: (Reset.Options) throws ->Reset.Options) async throws {
        let options = try configure(.init(writeCheckpoint: false))
        let usecase = Reset(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func getResult(configure: (Result.Options) throws ->Result.Options) async throws -> Result.Response {
        let options = try configure(.init())
        let usecase = Result(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func getState(configure: (State.Options) throws ->State.Options) async throws -> State.Response {
        let options = try configure(.init())
        let usecase = State(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

}

extension Projections where Target == ContinuousProjectionTarget {
    public func create(name: String, query: String, configure: (ContinuousCreate.Options) throws ->ContinuousCreate.Options) async throws {
        let options = try configure(.init())
        let usecase = ContinuousCreate(name: name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target == PredefinedProjection {
    public func reset(configure: (Reset.Options) throws ->Reset.Options) async throws {
        let options = try configure(.init(writeCheckpoint: false))
        let usecase = Reset(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
