//
//  Operations.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct Operations: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_Operations_Operations.Client<HTTP2ClientTransport.Posix>

    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    public init(settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Operations {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> StartScavenge.Response {
        let usecase = StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func stopScavenge(scavengeId: String) async throws -> StopScavenge.Response {
        let usecase = StopScavenge(scavengeId: scavengeId)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func mergeIndeexes() async throws {
        let usecase = MergeIndexes()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func resignNode() async throws {
        let usecase = ResignNode()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func restartPersistentSubscriptions() async throws {
        let usecase = RestartPersistentSubscriptions()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func setNodePriority(priority: Int32) async throws {
        let usecase = SetNodePriority(priority: priority)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func shutdown() async throws {
        let usecase = Shutdown()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
