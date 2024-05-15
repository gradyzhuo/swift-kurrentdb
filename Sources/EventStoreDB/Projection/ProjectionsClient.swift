//
//  Projection.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//
import Foundation
import GRPC
import GRPCEncapsulates
import SwiftProtobuf

public struct ProjectionsClient: GRPCConcreteClient {
    public typealias UnderlyingClient = EventStore_Client_Projections_ProjectionsAsyncClient

//    public private(set) var mode: Mode
    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions

//    init(mode: Mode, channel: GRPCChannel, callOptions: CallOptions) {
//        self.channel = channel
//        self.callOptions = callOptions
//        self.mode = mode
//    }

    init(channel: GRPCChannel, callOptions: CallOptions) {
        self.channel = channel
        self.callOptions = callOptions
    }

//    public init(name: String, emitEnable: Bool, trackEmittedStreams: Bool, channel: GRPCChannel, callOptions: CallOptions) throws {
//        self.init(mode: .continuous(name: name, emitEnable: emitEnable, trackEmittedStreams: trackEmittedStreams), channel: channel, callOptions: callOptions)
//    }
}

extension ProjectionsClient {
    public enum Mode {
//        case oneTime
//        case transient(name: String)
        case continuous(name: String, emitEnable: Bool, trackEmittedStreams: Bool)

        public var name: String? {
            switch self {
            case let .continuous(name, _, _):
                name
            }
        }
    }
}

extension ProjectionsClient {
    // MARK: - Create Actions

    func create(mode: Mode, query: String) async throws {
        switch mode {
//        case .oneTime:
//            $0.oneTime = .init()
//        case let .transient(name):
//            $0.transient = .with{
//                $0.name = name
//            }
        case let .continuous(name, emitEnable, trackEmittedStreams):
            let options: ContinuousCreate.Options =
                .init()
                    .emit(enabled: emitEnable)
                    .trackEmittedStreams(trackEmittedStreams)
            let handler = ContinuousCreate(name: name, query: query, options: options)
            let request = try handler.build()
            _ = try await handler.handle(response: underlyingClient.create(request))
        }
    }

    public func createForContinuous(name: String, emitEnable: Bool, trackEmittedStreams: Bool, query: String) async throws {
        let mode: Mode = .continuous(name: name, emitEnable: emitEnable, trackEmittedStreams: trackEmittedStreams)
        try await create(mode: mode, query: query)
    }

//    public static func create(name: String, query: String, channel: GRPCChannel, callOptions: CallOptions, configure: (_ options: ContinuousCreate.Options) -> ContinuousCreate.Options) async throws -> Self {
//        let options = configure(.init())
//
//        let mode: Mode = .continuous(name: name, emitEnable: options.emitEnabled, trackEmittedStreams: options.trackEmittedStreams)
//        return try await create(mode: mode, query: query, channel: channel, callOptions: callOptions)
//    }

    // MARK: - Update Actions

    public func updateForContinuous(name: String, query: String? = nil, options: Update.Options) async throws {
        let handler = Update(name: name, query: query, options: options)
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
    }

    public func updateForContinuous(name: String, query: String? = nil, configure: (_ options: Update.Options) -> Update.Options) async throws {
        let options = configure(.init())
        try await updateForContinuous(name: name, query: query, options: options)
    }

    // MARK: - Delete Actions

    public func deleteForContinuous(name: String, options: Delete.Options) async throws {
        let handler = Delete(name: name, options: options)

        let request = try handler.build()
        try await handler.handle(response: underlyingClient.delete(request))
    }

    public func deleteForContinuous(name: String, configure: (_ options: Delete.Options) -> Delete.Options) async throws {
        let options = configure(.init())
        try await deleteForContinuous(name: name, options: options)
    }

    // MARK: - Statistics Actions

    package func statisticsForContinuous(name: String) async throws -> Statistics.Responses {
        let handler = Statistics(name: name, options: .init().set(mode: .continuous))
        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.statistics(request))
    }

    package func statistics(name: String, options: Statistics.Options) async throws -> Statistics.Responses {
        let handler = Statistics(name: name, options: options)

        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.statistics(request))
    }

    package func statistics(name: String, configure: (_ options: Statistics.Options) -> Statistics.Options) async throws -> Statistics.Responses {
        let handler = Statistics(name: name, options: configure(.init()))

        let request = try handler.build()
        return try handler.handle(responses: underlyingClient.statistics(request))
    }

    // MARK: - Enable Actions

    public func enable(name: String) async throws {
        let options = Enable.Options()
        try await enable(name: name, options: options)
    }

    func enable(name: String, options: Enable.Options) async throws {
        let handler = Enable(name: name, options: options)

        let request = try handler.build()
        try await handler.handle(response: underlyingClient.enable(request))
    }

    // MARK: - Disable & Abort Actions

    public func disable(name: String) async throws {
        let options = Disable.Options().writeCheckpoint(enabled: true)
        return try await disable(name: name, options: options)
    }

    public func abort(name: String) async throws {
        let options = Disable.Options().writeCheckpoint(enabled: false)
        return try await disable(name: name, options: options)
    }

    func disable(name: String, options: Disable.Options) async throws {
        let handler = Disable(name: name, options: options)

        let request = try handler.build()
        try await handler.handle(response: underlyingClient.disable(request))
    }

    // MARK: - Reset Actions

    public func reset(name: String) async throws {
        let options: Reset.Options = .init().writeCheckpoint(enable: false)
        try await reset(name: name, options: options)
    }

    func reset(name: String, options: Reset.Options) async throws {
        let handler = Reset(name: name, options: options)

        let request = try handler.build()
        try await handler.handle(response: underlyingClient.reset(request))
    }

    // MARK: - State Actions

    public func getState<Value: Decodable>(name: String, casting _: Value.Type, options: State.Options) async throws -> Value {
        let handler = State(name: name, options: options)
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.state(request))
        return try response.decode(to: Value.self)
    }

    public func getState<Value: Decodable>(name: String, casting: Value.Type, configure: (_ options: State.Options) -> State.Options) async throws -> Value {
        let options = configure(.init())
        return try await getState(name: name, casting: casting, options: options)
    }

    public func getState<Value: Decodable>(name: String, configure: (_ options: State.Options) -> State.Options) async throws -> Value {
        let options = configure(.init())
        return try await getState(name: name, casting: Value.self, options: options)
    }

    // MARK: - Result Actions

    public func getResult<Value: Decodable>(name: String, casting _: Value.Type, options: Result.Options) async throws -> Value {
        let handler = Result(name: name, options: options)
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.result(request))

        return try response.decode(to: Value.self)
    }

    public func getResult<Value: Decodable>(name: String, casting: Value.Type, configure: (_ options: Result.Options) -> Result.Options) async throws -> Value {
        let options = configure(.init())
        return try await getResult(name: name, casting: casting, options: options)
    }

    public func getResult<Value: Decodable>(name: String, configure: (_ options: Result.Options) -> Result.Options) async throws -> Value {
        let options = configure(.init())
        return try await getResult(name: name, casting: Value.self, options: options)
    }

    // MARK: - RestartSubsystem Actions

    public func restartSubsystem(settings _: ClientSettings = EventStore.shared.settings) async throws {
        let handler = RestartSubsystem()
        try await handler.handle(response: underlyingClient.restartSubsystem(handler.build()))
    }
}
