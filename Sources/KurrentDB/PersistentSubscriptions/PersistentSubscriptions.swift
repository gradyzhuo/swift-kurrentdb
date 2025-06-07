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

public actor PersistentSubscriptions<Target: PersistentSubscriptionTarget>: GRPCConcreteService {
    /// The underlying gRPC service type.
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions
    
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = UnderlyingService.Client<HTTP2ClientTransport.Posix>

    /// The settings used for client communication.
    public private(set) var selector: NodeSelector
    
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
    internal init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
        self.target = target
    }
}

extension PersistentSubscriptions {
    public struct SpecifiedStream {}
    public struct AllStream {}
}

//MARK: - Streams
extension Streams where Target: SpecifiedStreamTarget{
    /// Returns a `PersistentSubscriptions` instance for a specified stream and subscription group.
    ///
    /// - Parameter group: The name of the persistent subscription group.
    /// - Returns: A `PersistentSubscriptions` actor scoped to the given stream identifier and group.
    public func persistentSubscriptions(group: String)->PersistentSubscriptions<PersistentSubscription.Specified> {
        let target = PersistentSubscription.Specified(identifier: target.identifier, group: group)
        return .init(target: target, selector: selector, callOptions: callOptions)
    }
}

extension Streams where Target == AllStreams{
    public func persistentSubscriptions(group: String)->PersistentSubscriptions<PersistentSubscription.AllStream> {
        let target = PersistentSubscription.AllStream(group: group)
        return .init(target: target, selector: selector, callOptions: callOptions)
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
    
    /// Creates a persistent subscription for all streams with the specified options.
    ///
    /// - Parameter options: Configuration options for creating the persistent subscription. Defaults to the standard options.
    ///
    /// - Throws: `KurrentError` if the subscription could not be created.
    public func create(options: AllStream.Create.Options = .init()) async throws(KurrentError) {
        let usecase = AllStream.Create(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Updates the persistent subscription for all streams with the specified options.
    ///
    /// - Parameter options: Configuration options for updating the persistent subscription. Defaults to an empty options set.
    /// - Throws: `KurrentError` if the update operation fails.
    public func update(options: AllStream.Update.Options = .init()) async throws(KurrentError) {
        let usecase = AllStream.Update(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// Deletes the persistent subscription group for all streams.
    ///
    /// - Throws: `KurrentError` if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = AllStream.Delete(group: group)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Retrieves information about the persistent subscription group for all streams.
    ///
    /// - Returns: Details of the persistent subscription group.
    /// - Throws: `KurrentError` if the operation fails.
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = AllStream.GetInfo(group: group)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Subscribes to a persistent subscription for all streams using the specified options.
    ///
    /// - Parameter options: Configuration options for the subscription. Defaults to `.init()`.
    /// - Returns: A `Subscription` instance representing the active persistent subscription.
    /// - Throws: `KurrentError` if the subscription could not be established.
    public func subscribe(options: AllStream.Read.Options = .init()) async throws(KurrentError) -> Subscription {
        let usecase = AllStream.Read(group: group, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Replays parked messages for the persistent subscription group across all streams.
    ///
    /// - Parameter options: Configuration options for replaying parked messages. Defaults to `.init()`.
    /// - Throws: `KurrentError` if the operation fails.
    public func replayParked(options: AllStream.ReplayParked.Options = .init()) async throws(KurrentError) {
        let usecase = AllStream.ReplayParked(group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
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

    /// Creates a persistent subscription for a specified stream with the given options.
    ///
    /// - Parameter options: Configuration options for creating the persistent subscription. Defaults to `.init()`.
    /// - Throws: `KurrentError` if the subscription could not be created.
    public func create(options: SpecifiedStream.Create.Options = .init()) async throws(KurrentError) {
        let usecase = SpecifiedStream.Create(streamIdentifier: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    
    /// Updates the persistent subscription for the specified stream with the provided options.
    ///
    /// - Parameter options: Configuration options for updating the persistent subscription.
    /// - Throws: `KurrentError` if the update operation fails.
    public func update(options: SpecifiedStream.Update.Options = .init()) async throws(KurrentError) {
        let usecase = SpecifiedStream.Update(streamIdentifier: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// Deletes the persistent subscription for the specified stream and group.
    ///
    /// - Throws: `KurrentError` if the deletion fails.
    public func delete() async throws(KurrentError) {
        let usecase = SpecifiedStream.Delete(streamIdentifier: target.identifier, group: target.group)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Retrieves information about the persistent subscription for the specified stream and group.
    ///
    /// - Returns: Subscription information for the targeted stream and group.
    /// - Throws: `KurrentError` if the operation fails.
    public func getInfo() async throws(KurrentError) -> PersistentSubscription.SubscriptionInfo {
        let usecase = SpecifiedStream.GetInfo(stream: target.identifier, group: group)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Subscribes to a persistent subscription on a specified stream.
    ///
    /// - Parameter options: Options for configuring the subscription. Defaults to `.init()`.
    /// - Returns: A `Subscription` representing the active persistent subscription.
    /// - Throws: `KurrentError` if the subscription could not be established.
    public func subscribe(options: SpecifiedStream.Read.Options = .init()) async throws(KurrentError) -> Subscription {
        let usecase = SpecifiedStream.Read(stream: target.identifier, group: group, options: options)
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Replays parked messages for the specified persistent subscription stream.
    ///
    /// - Parameter options: Options to configure the replay operation. Defaults to `.init()`.
    /// - Throws: `KurrentError` if the replay operation fails.
    public func replayParked(options: SpecifiedStream.ReplayParked.Options = .init()) async throws(KurrentError) {
        let usecase = SpecifiedStream.ReplayParked(stream: target.identifier, group: group, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
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
        return try await usecase.perform(selector: selector, callOptions: callOptions)
    }
    
    /// Restarts the subsystem managing persistent subscriptions.
    ///
    /// Restarts the persistent subscription subsystem asynchronously.
    ///
    /// This operation reinitializes the persistent subscription infrastructure on the server side.
    /// Throws a `KurrentError` if the restart fails.
    @MainActor
    public func restartSubsystem() async throws(KurrentError) {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

}

