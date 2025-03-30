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

public struct PersistentSubscriptions<Target: PersistentSubscriptionTarget>: GRPCConcreteService {
    /// The underlying gRPC service type.
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions
    
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = UnderlyingService.Client<HTTP2ClientTransport.Posix>

    /// The settings used for client communication.
    public private(set) var clientSettings: ClientSettings
    
    /// Options to be used for each gRPC service call.
    public var callOptions: CallOptions
    
    /// The event loop group for asynchronous execution.
    public let eventLoopGroup: EventLoopGroup
    
    /// The target stream for the subscription (e.g., specific stream, all streams, or generic).
    public let target: Target

    /// Initializes a `PersistentSubscriptions` instance.
    ///
    /// - Parameters:
    ///   - target: The target stream for the subscription (e.g., `Specified`, `All`, or `AnyTarget`).
    ///   - settings: The settings used for client communication.
    ///   - callOptions: Options for the gRPC call, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group for async operations, defaulting to `.singletonMultiThreadedEventLoopGroup`.
    internal init(target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.clientSettings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
        self.target = target
    }
}

//MARK: - Streams

extension Streams where Target: SpecifiedStreamTarget{
    public func persistentSubscriptions(group: String)->PersistentSubscriptions<PersistentSubscription.Specified> {
        let target = PersistentSubscription.Specified(identifier: target.identifier, group: group)
        return .init(target: target, settings: settings, callOptions: callOptions)
    }
}

extension Streams where Target == AllStreams{
    public func persistentSubscriptions(group: String)->PersistentSubscriptions<PersistentSubscription.AllStream> {
        let target = PersistentSubscription.AllStream(group: group)
        return .init(target: target, settings: settings, callOptions: callOptions)
    }
}


//MARK: - PersistentSubscription
extension PersistentSubscriptions where Target == PersistentSubscription.AllStream {
    /// The group name of the persistent subscription.
    public var group: String {
        get {
            target.group
        }
    }
    
    public func create(startFrom cursor: PositionCursor = .end, options: Create.Options = .init()) async throws(KurrentError) {
        let usecase = Create(stream: .all(cursor: cursor), group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    public func update(startFrom cursor: PositionCursor = .end, options: Update.Options = .init()) async throws(KurrentError) {
        let usecase = Update(stream: .all(cursor: cursor), group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// - Throws: An error if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = Delete(group: group)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(group: group)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    public func subscribe(options: ReadOptions = .init()) async throws(KurrentError) -> Subscription {
        let usecase = Read(group: group, options: options)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    public func replayParked(options: ReplayParked.Options = .init()) async throws(KurrentError) {
        let usecase = ReplayParked(group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
}



//MARK: - PersistentSubscription
extension PersistentSubscriptions where Target == PersistentSubscription.Specified {
    /// The group name of the persistent subscription.
    public var group: String {
        get {
            target.group
        }
    }

    public func create(startFrom cursor: RevisionCursor = .end, options: Create.Options = .init()) async throws(KurrentError) {
        let usecase = Create(stream: .specified(identifier: target.identifier, cursor: cursor), group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    
    public func update(startFrom cursor: RevisionCursor = .end, options: Update.Options = .init()) async throws(KurrentError) {
        let usecase = Update(stream: .specified(identifier: target.identifier, cursor: cursor), group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// - Throws: An error if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = Delete(stream: target.identifier, group: target.group)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(stream: target.identifier, group: group)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    public func subscribe(options: ReadOptions = .init()) async throws(KurrentError) -> Subscription {
        let usecase = Read(stream: target.identifier, group: group, options: options)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    public func replayParked(options: ReplayParked.Options = .init()) async throws(KurrentError) {
        let usecase = ReplayParked(stream: target.identifier, group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
}


// MARK: - Generic Operations
/// Provides general operations for persistent subscriptions with an unspecified target.
extension PersistentSubscriptions where Target == PersistentSubscription.All {
    
    /// Lists all persistent subscriptions in the system.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    public func list(for filter: PersistentSubscriptions.ListForAll.ListFilter = .allSubscriptions) async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        let usecase = ListForAll(filter: filter)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Restarts the subsystem managing persistent subscriptions.
    ///
    /// - Throws: An error if the restart operation fails.
    @MainActor
    public func restartSubsystem() async throws(KurrentError) {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }

}


//extension PersistentSubscriptions{
//    
//    
//    
//    /// Lists all persistent subscriptions in the system.
//    ///
//    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
//    /// - Throws: An error if the list operation fails.
//    public func list(filter: PersistentSubscriptions.ListForAll.ListFilter = .allSubscriptions) async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
//        let usecase = ListForAll(filter: filter)
//        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
//    }
//    
//    /// Restarts the subsystem managing persistent subscriptions.
//    ///
//    /// - Throws: An error if the restart operation fails.
//    @MainActor
//    public func restartSubsystem() async throws(KurrentError) {
//        let usecase = RestartSubsystem()
//        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
//    }
//}
