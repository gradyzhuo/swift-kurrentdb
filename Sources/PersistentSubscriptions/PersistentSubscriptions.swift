//
//  PersistentSubscriptionsClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import KurrentCore
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

public typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions

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
    // MARK: - Create Action

    public func createToStream(streamIdentifier: KurrentCore.Stream.Identifier, groupName: String, options: CreateToStream.Options) async throws {
        let usecase: CreateToStream = .init(streamIdentifier: streamIdentifier, groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func createToAll(groupName: String, options: PersistentSubscriptions.CreateToAll.Options) async throws {
        let usecase: PersistentSubscriptions.CreateToAll = .init(groupName: groupName, options: options)
        _ =  try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Update Action

    public func updateToStream(identifier: KurrentCore.Stream.Identifier, groupName: String, options: UpdateToStream.Options) async throws {
        let usecase = UpdateToStream(streamIdentifier: identifier, groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func updateToAll(identifier _: KurrentCore.Stream.Identifier, groupName: String, options: UpdateToAll.Options) async throws {
        let usecase = UpdateToAll(groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Delete Actions

    public func delete(stream: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String) async throws {
        let usecase = Delete(streamSelection: stream, groupName: groupName)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Read Actions

    public func subscribe(_ streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String, options: Read.Options) async throws -> Subscription {
        let usecase = Read(streamSelection: streamSelection, groupName: groupName, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - GetInfo Action

    public func getInfo(stream streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String) async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(streamSelection: streamSelection, groupName: groupName)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - ReplayParked Action

    public func replayParkedMessages(stream streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String, options: ReplayParked.Options) async throws {
        let usecase = ReplayParked(streamSelection: streamSelection, groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func replayParkedMessages(stream streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String, configure: (_ options: ReplayParked.Options) -> ReplayParked.Options) async throws {
        try await replayParkedMessages(stream: streamSelection, groupName: groupName, options: configure(.init()))
    }

    // MARK: - List Action

    public func list(streamSelector: KurrentCore.Selector<KurrentCore.Stream.Identifier>) async throws -> [PersistentSubscription.SubscriptionInfo] {
        let options: List.Options = switch streamSelector {
        case .all: .listAllScriptions()
        case .specified(let streamIdentifier): try .listForStream(streamIdentifier)
        }

        let usecase = List(options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Restart Subsystem Action

    @MainActor
    public func restartSubsystem() async throws {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
