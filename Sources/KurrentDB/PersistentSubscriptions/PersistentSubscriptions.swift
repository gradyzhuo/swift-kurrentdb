//
//  PersistentSubscriptions.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/7.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct PersistentSubscriptions<Target: StreamTarget>: GRPCConcreteService {
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions
    package typealias UnderlyingClient = UnderlyingService.Client<HTTP2ClientTransport.Posix>

    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup
    public let target: Target

    public init(stream target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
        self.target = target
    }
}

extension PersistentSubscriptions where Target == AllStreams {
    // MARK: - Create Action
    public func create(group: String, options: CreateToAll.Options = .init()) async throws {
        let usecase: CreateToAll = .init(group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    // MARK: - Update Action
    public func update(group: String, options: UpdateToAll.Options = .init()) async throws {
        let usecase = UpdateToAll(group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    // MARK: - Delete Actions
    public func delete(group: String) async throws {
        let usecase = Delete(stream: .all, group: group)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    // MARK: - Read Actions
    public func subscribe(group: String, options: Read.Options = .init()) async throws -> Subscription {
        let usecase = Read(streamSelection: .all, group: group, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    // MARK: - GetInfo Action
    public func getInfo(group: String) async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(stream: .all, group: group)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    // MARK: - ReplayParked Action
    public func replayParkedMessages(group: String, options: ReplayParked.Options = .init()) async throws {
        let usecase = ReplayParked(streamSelection: .all, group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    // MARK: - List Action
    public func list() async throws -> [PersistentSubscription.SubscriptionInfo] {
        let options: List.Options = .listAllScriptions()
        let usecase = List(options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension PersistentSubscriptions where Target == SpecifiedStream{
    
    public var streamIdentifier: StreamIdentifier {
        get{
            target.identifier
        }
    }
    
    // MARK: - Create Action
    public func create(group: String, options: CreateToStream.Options = .init()) async throws {
        let usecase: CreateToStream = .init(streamIdentifier: streamIdentifier, group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Update Action
    public func update(group: String, options: UpdateToStream.Options = .init()) async throws {
        let usecase = UpdateToStream(streamIdentifier: streamIdentifier, group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }


    // MARK: - Delete Actions
    public func delete(group: String) async throws {
        let usecase = Delete(stream: .specified(streamIdentifier), group: group)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Read Actions
    public func subscribe(group: String, options: Read.Options = .init()) async throws -> Subscription {
        let usecase = Read(streamSelection: .specified(streamIdentifier), group: group, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - GetInfo Action
    public func getInfo(group: String) async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(stream: .specified(streamIdentifier), group: group)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - ReplayParked Action

    public func replayParkedMessages(group: String, options: ReplayParked.Options = .init()) async throws {
        let usecase = ReplayParked(streamSelection: .specified(streamIdentifier), group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - List Action
    public func list() async throws -> [PersistentSubscription.SubscriptionInfo] {
        let options: List.Options = try .listForStream(streamIdentifier)
        let usecase = List(options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension PersistentSubscriptions {
    // MARK: - Restart Subsystem Action
    @MainActor
    public func restartSubsystem() async throws {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
