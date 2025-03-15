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

/// A service for managing persistent subscriptions to streams.
///
/// `PersistentSubscriptions` allows you to create, update, delete, subscribe to, and retrieve information
/// about persistent subscriptions for streams in the EventStore system. It supports operations on both
/// all streams and specified streams, depending on the provided `Target`.
///
/// ## Usage Example:
/// ```swift
/// let persistentSubscriptions = PersistentSubscriptions<SpecifiedStream>(stream: .specified("streamName"),
///                                                                         settings: clientSettings)
/// try await persistentSubscriptions.create(group: "subscriptionGroup")
/// ```
///
/// - SeeAlso: `AllStreams` and `SpecifiedStream` for selecting different stream targets.
public struct PersistentSubscriptions<Target: PersistenSubscriptionTarget>: GRPCConcreteService {
    package typealias UnderlyingService = EventStore_Client_PersistentSubscriptions_PersistentSubscriptions
    package typealias UnderlyingClient = UnderlyingService.Client<HTTP2ClientTransport.Posix>

    /// The settings used for client communication.
    public private(set) var settings: ClientSettings
    
    /// Options to be used for each service call.
    public var callOptions: CallOptions
    
    /// The event loop group for asynchronous execution.
    public let eventLoopGroup: EventLoopGroup
    
    /// The target stream, which could be either `AllStreams` or a `SpecifiedStream`.
    public let target: Target

    /// Initializes a new instance of `PersistentSubscriptions`.
    ///
    /// - Parameters:
    ///   - target: The target stream for the subscription, either a specific stream or all streams.
    ///   - settings: The settings used for client communication.
    ///   - callOptions: Options for the gRPC call (default is `.defaults`).
    ///   - eventLoopGroup: The event loop group for async operations (default is `.singletonMultiThreadedEventLoopGroup`).
    internal init(target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
        self.target = target
    }
}


// MARK: - All Streams
extension PersistentSubscriptions where Target == PersistentSubscription.All {
    /// The stream identifier for the specified stream.
    public var group: String {
        get{
            target.group
        }
    }
    /// Creates a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for the subscription (default is `.init()`).
    public func create(options: CreateToAll.Options = .init()) async throws {
        let usecase: CreateToAll = .init(group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Updates a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for the update (default is `.init()`).
    public func update(options: UpdateToAll.Options = .init()) async throws {
        let usecase = UpdateToAll(group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    public func delete() async throws {
        let usecase = Delete(stream: .all, group: group)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Subscribes to a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for the subscription (default is `.init()`).
    /// - Returns: A `Subscription` object for managing the subscription.
    public func subscribe(options: Read.Options = .init()) async throws -> Subscription {
        let usecase = Read(streamSelection: .all, group: group, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Retrieves information about a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    /// - Returns: A `PersistentSubscription.SubscriptionInfo` object with subscription details.
    public func getInfo() async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(stream: .all, group: group)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Replays parked messages for a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for replaying the parked messages (default is `.init()`).
    public func replayParkedMessages(options: ReplayParked.Options = .init()) async throws {
        let usecase = ReplayParked(streamSelection: .all, group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}


//MARK: - Specified Stream
extension PersistentSubscriptions where Target == PersistentSubscription.Specified {
    
    /// The stream identifier for the specified stream.
    public var streamIdentifier: StreamIdentifier {
        get{
            target.identifier
        }
    }
    
    /// The stream identifier for the specified stream.
    public var group: String {
        get{
            target.group
        }
    }
    
    /// Creates a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for the subscription (default is `.init()`).
    public func create(options: CreateToStream.Options = .init()) async throws {
        let usecase: CreateToStream = .init(streamIdentifier: streamIdentifier, group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Updates a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for the update (default is `.init()`).
    public func update(options: UpdateToStream.Options = .init()) async throws {
        let usecase = UpdateToStream(streamIdentifier: streamIdentifier, group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Deletes a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    public func delete() async throws {
        let usecase = Delete(stream: .specified(streamIdentifier), group: group)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Subscribes to a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for the subscription (default is `.init()`).
    /// - Returns: A `Subscription` object for managing the subscription.
    public func subscribe(options: Read.Options = .init()) async throws -> Subscription {
        let usecase = Read(streamSelection: .specified(streamIdentifier), group: group, options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Retrieves information about a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    /// - Returns: A `PersistentSubscription.SubscriptionInfo` object with subscription details.
    public func getInfo() async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(stream: .specified(streamIdentifier), group: group)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    /// Replays parked messages for a persistent subscription for a specified stream.
    ///
    /// - Parameters:
    ///   - group: The subscription group name.
    ///   - options: Options for replaying the parked messages (default is `.init()`).
    public func replayParkedMessages(options: ReplayParked.Options = .init()) async throws {
        let usecase = ReplayParked(streamSelection: .specified(streamIdentifier), group: group, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }

    
}

extension PersistentSubscriptions where Target == PersistentSubscription.AnyTarget {
    /// Restarts the subsystem for managing persistent subscriptions.
    @MainActor
    public func restartSubsystem() async throws {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    
    /// Lists all persistent subscriptions for a specified stream.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    public func listForStream(_ streamIdentifier: StreamIdentifier) async throws -> [PersistentSubscription.SubscriptionInfo] {
        let options: List.Options = try .listForStream(streamIdentifier)
        let usecase = List(options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Lists all persistent subscriptions.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    public func listAll() async throws -> [PersistentSubscription.SubscriptionInfo] {
        let options: List.Options = .listAllScriptions()
        let usecase = List(options: options)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
