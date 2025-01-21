//
//  OperationsClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import KurrentCore
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

public typealias UnderlyingService = EventStore_Client_Operations_Operations

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
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> StartScavenge.Response {
        let usecase = StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func stopScavenge(scavengeId: String) async throws -> StopScavenge.Response {
        let usecase = StopScavenge(scavengeId: scavengeId)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func mergeIndeexes() async throws{
        let usecase = MergeIndexes()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func resignNode() async throws{
        let usecase = ResignNode()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func restartPersistentSubscriptions() async throws{
        let usecase = RestartPersistentSubscriptions()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func setNodePriority(priority: Int32) async throws{
        let usecase = SetNodePriority(priority: priority)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    public func shutdown() async throws{
        let usecase = Shutdown()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
