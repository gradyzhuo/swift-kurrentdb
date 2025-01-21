//
//  Projection.swift
//
//
//  Created by Grady Zhuo on 2023/10/17.
//
import Foundation
import KurrentCore
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import SwiftProtobuf

public typealias UnderlyingService = EventStore_Client_Projections_Projections
public struct Service: GRPCConcreteClient {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias UnderlyingClient = UnderlyingService.Client<Transport>
    
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults){
        self.settings = settings
        self.callOptions = callOptions
    }
}

extension Service {
    public func create(name: String, query: String, options: ContinuousCreate.Options) async throws -> ContinuousCreate.Response {
        let usecase = ContinuousCreate(name: name, query: query, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func delete(name: String, options: Delete.Options) async throws -> Delete.Response {
        let usecase = Delete(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func disable(name: String, options: Disable.Options) async throws -> Disable.Response {
        let usecase = Disable(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func enable(name: String, options: Enable.Options) async throws -> Enable.Response {
        let usecase = Enable(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func reset(name: String, options: Reset.Options) async throws -> Reset.Response {
        let usecase = Reset(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func state(name: String, options: State.Options) async throws -> State.Response {
        let usecase = State(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func statistics(name: String, options: Statistics.Options) async throws -> Statistics.Responses {
        let usecase = Statistics(name: name, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func update(name: String, query: String?, options: Update.Options) async throws -> Update.Response {
        let usecase = Update(name: name, query: query, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
