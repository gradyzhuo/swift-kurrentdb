//
//  Projections.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/10/17.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct Projections<Target: ProjectionTarget>: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_Projections_Projections.Client<HTTP2ClientTransport.Posix>

    private(set) var settings: ClientSettings
    var callOptions: CallOptions
    let eventLoopGroup: EventLoopGroup
    private(set) var target: Target

    internal init(target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}


extension Projections where Target: NameSpecifiable & ProjectionCreatable{
    public func continousCreate(query: String, options: ContinuousCreate.Options = .init()) async throws {
        let usecase = ContinuousCreate(name: target.name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func continousCreate(query: String, configure: (ContinuousCreate.Options) throws ->ContinuousCreate.Options) async throws {
        let options = try configure(.init())
        let usecase = ContinuousCreate(name: target.name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable {
    var name: String {
        target.name
    }
}

extension Projections where Target == AllProjectionTarget<ContinuousMode> {
    
    public func list() async throws -> [Statistics.Detail] {
        let usecase = Statistics(options: .listAll(mode: target.mode.mode))
        return try await usecase.perform(settings: settings, callOptions: callOptions).reduce(into: .init()) { partialResult, response in
            partialResult.append(response.detail)
        }
    }
    
}

extension Projections where Target == AllProjectionTarget<AnyMode> {
    
    public func list() async throws -> [Statistics.Detail] {
        let usecase = Statistics(options: .listAll(mode: target.mode.mode))
        return try await usecase.perform(settings: settings, callOptions: callOptions).reduce(into: .init()) { partialResult, response in
            partialResult.append(response.detail)
        }
    }
    
}

extension Projections where Target: NameSpecifiable & ProjectionEnable {
    public func enable() async throws {
        let usecase = Enable(name: name, options: .init())
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionDisable{
    public func disable(writeCheckpoint _: Bool = false) async throws {
        let options = Disable.Options().writeCheckpoint(enabled: false)
        let usecase = Disable(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func disable(configure: (Disable.Options) throws ->Disable.Options) async throws {
        let options = try configure(.init(writeCheckpoint: false))
        let usecase = Disable(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func abort() async throws {
        let options = Disable.Options().writeCheckpoint(enabled: false)
        let usecase = Disable(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionResetable {
    public func reset(writeCheckpoint: Bool = false) async throws {
        let options = Reset.Options().writeCheckpoint(enable: writeCheckpoint)
        let usecase = Reset(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func reset(configure: (Reset.Options) throws ->Reset.Options) async throws {
        let options = try configure(.init(writeCheckpoint: false))
        let usecase = Reset(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}



extension Projections where Target: NameSpecifiable & ProjectionDeletable {
    public func delete(deleteCheckpointStream: Bool = false, deleteEmittedStreams: Bool = false, deleteStateStream: Bool = false) async throws {
        let options = Delete.Options()
            .deleteCheckpointStream(enabled: deleteCheckpointStream)
            .deleteEmittedStreams(enabled: deleteEmittedStreams)
            .deleteStateStream(enabled: deleteStateStream)
        let usecase = Delete(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func delete(configure: (Delete.Options) throws ->Delete.Options = { $0 }) async throws {
        let options = try configure(.init())
        let usecase = Delete(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
}


extension Projections where Target: NameSpecifiable & ProjectionUpdatable {
    public func update(query: String?, emit emitOption: Update.EmitOption = .noEmit) async throws {
        let options = Update.Options(emitOption: emitOption)
        let usecase = Update(name: name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func update(query: String?, configure: (Update.Options) throws ->Update.Options) async throws {
        let options = try configure(.init(emitOption: .noEmit))
        let usecase = Update(name: name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionDescribable {
    public func detail() async throws -> Statistics.Detail? {
        let usecase = Statistics(options: .specified(name: name))
        let response = try await usecase.perform(settings: settings, callOptions: callOptions).first{ _ in true }
        return response?.detail
    }
}

extension Projections where Target: NameSpecifiable & ProjectionResulable{
    public func result<DecodeType: Decodable>(of _: DecodeType.Type, partition: String? = nil) async throws -> DecodeType? {
        let options = Result.Options(partition: partition)
        let usecase = Result(name: name, options: options)
        let response = try await usecase.perform(settings: settings, callOptions: callOptions)
        return try response.decode(to: DecodeType.self)
    }
    
    public func result(configure: (Result.Options) throws ->Result.Options) async throws -> Result.Response {
        let options = try configure(.init())
        let usecase = Result(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func state<DecodeType: Decodable>(of _: DecodeType.Type, partition: String? = nil) async throws -> DecodeType? {
        let options = State.Options(partition: partition)
        let usecase = State(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions).decode(to: DecodeType.self)
    }
    
    public func state(configure: (State.Options) throws ->State.Options) async throws -> State.Response {
        let options = try configure(.init())
        let usecase = State(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
