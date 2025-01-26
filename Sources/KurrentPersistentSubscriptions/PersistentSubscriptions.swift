//
//  PersistentSubscriptionsClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

@_exported
import KurrentCore

import Foundation
import NIO
import Logging
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix


public struct PersistentSubscriptions: GRPCConcreteService {
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions
    package typealias Client = UnderlyingService.Client<HTTP2ClientTransport.Posix>
    
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup){
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension PersistentSubscriptions {
    // MARK: - Create Action

    public func createToStream(streamIdentifier: StreamIdentifier, groupName: String, options: CreateToStream.Options = .init()) async throws {
        let usecase: CreateToStream = .init(streamIdentifier: streamIdentifier, groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func createToAll(groupName: String, options: CreateToAll.Options = .init()) async throws {
        let usecase: CreateToAll = .init(groupName: groupName, options: options)
        _ =  try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Update Action

    public func updateToStream(identifier: StreamIdentifier, groupName: String, options: UpdateToStream.Options = .init()) async throws {
        let usecase = UpdateToStream(streamIdentifier: identifier, groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    public func updateToAll(identifier _: StreamIdentifier, groupName: String, options: UpdateToAll.Options = .init()) async throws {
        let usecase = UpdateToAll(groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Delete Actions

    public func delete(stream: StreamSelector<StreamIdentifier>, groupName: String) async throws {
        let usecase = Delete(streamSelection: stream, groupName: groupName)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - Read Actions

    public func subscribe(_ streamSelection: StreamSelector<StreamIdentifier>, groupName: String, options: Read.Options) async throws -> Subscription {
        let usecase = Read(streamSelection: streamSelection, groupName: groupName, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - GetInfo Action

    public func getInfo(stream streamSelection: StreamSelector<StreamIdentifier>, groupName: String) async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(streamSelection: streamSelection, groupName: groupName)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - ReplayParked Action

    public func replayParkedMessages(stream streamSelection: StreamSelector<StreamIdentifier>, groupName: String, options: ReplayParked.Options = .init()) async throws {
        let usecase = ReplayParked(streamSelection: streamSelection, groupName: groupName, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    // MARK: - List Action

    public func list(streamSelector: StreamSelector<StreamIdentifier>) async throws -> [PersistentSubscription.SubscriptionInfo] {
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
