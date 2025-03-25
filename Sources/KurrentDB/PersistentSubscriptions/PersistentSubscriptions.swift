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
/// `PersistentSubscriptions` provides methods to create, update, delete, subscribe to, and retrieve
/// information about persistent subscriptions in an EventStore system. The type parameter `Target`
/// determines whether the subscription applies to a specific stream (`Specified`), all streams (`All`),
/// or a generic target (`AnyTarget`).
///
/// ## Usage
///
/// Creating a persistent subscription to a specific stream:
/// ```swift
/// let subscription = PersistentSubscriptions(target: .specified("streamName", group: "myGroup"),
///                                            settings: clientSettings)
/// try await subscription.create()
/// ```
///
/// Subscribing to all streams:
/// ```swift
/// let subscription = PersistentSubscriptions(target: .all(group: "myGroup"), settings: clientSettings)
/// let sub = try await subscription.subscribe()
/// for try await event in sub.events {
///     print(event)
/// }
/// ```
///
/// - Note: This service relies on **gRPC** and requires a valid `ClientSettings` configuration.
///
/// ### Topics
/// #### Specific Stream Operations
/// - ``create(options:)-swift.struct-7k8n2``
/// - ``update(options:)-swift.struct-5m3j8``
/// - ``delete()-swift.struct-9p2k1``
/// - ``subscribe(options:)-swift.struct-3h7v9``
/// - ``getInfo()-swift.struct-1d5r4``
/// - ``replayParkedMessages(options:)-swift.struct-8t9m0``
///
/// #### All Streams Operations
/// - ``create(options:)-swift.struct-2x4p7``
/// - ``update(options:)-swift.struct-6y8q3``
/// - ``delete()-swift.struct-4z2n9``
/// - ``subscribe(options:)-swift.struct-9r5t1``
/// - ``getInfo()-swift.struct-7u3m8``
/// - ``replayParkedMessages(options:)-swift.struct-3v6k2``
///
/// #### General Operations
/// - ``restartSubsystem()``
/// - ``listForStream(_:)``
/// - ``listAll()``
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

// MARK: - All Streams
/// Provides operations for persistent subscriptions targeting all streams.
extension PersistentSubscriptions where Target == PersistentSubscription.All {
    /// The group name of the persistent subscription.
    public var group: String {
        get {
            target.group
        }
    }
    
    /// Creates a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - options: Configuration options for creating the subscription, defaulting to an empty configuration.
    /// - Throws: An error if the creation fails.
    public func create(options: CreateToAll.Options = .init()) async throws {
        let usecase: CreateToAll = .init(group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Updates an existing persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - options: Configuration options for updating the subscription, defaulting to an empty configuration.
    /// - Throws: An error if the update fails.
    public func update(options: UpdateToAll.Options = .init()) async throws {
        let usecase = UpdateToAll(group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// - Throws: An error if the deletion fails.
    public func delete() async throws {
        let usecase = Delete(stream: .all, group: group)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Subscribes to a persistent subscription for all streams.
    ///
    /// - Parameters:
    ///   - options: Configuration options for subscribing, defaulting to an empty configuration.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribe(options: Read.Options = .init()) async throws -> Subscription {
        let usecase = Read(streamSelection: .all, group: group, options: options)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Retrieves information about a persistent subscription for all streams.
    ///
    /// - Returns: A `PersistentSubscription.SubscriptionInfo` object containing subscription details.
    /// - Throws: An error if the information cannot be retrieved.
    public func getInfo() async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(stream: .all, group: group)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Replays parked messages for a persistent subscription targeting all streams.
    ///
    /// - Parameters:
    ///   - options: Configuration options for replaying parked messages, defaulting to an empty configuration.
    /// - Throws: An error if the replay operation fails.
    public func replayParkedMessages(options: ReplayParked.Options = .init()) async throws {
        let usecase = ReplayParked(streamSelection: .all, group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
}

// MARK: - Specified Stream
/// Provides operations for persistent subscriptions targeting a specific stream.
extension PersistentSubscriptions where Target == PersistentSubscription.Specified {
    /// The identifier of the specific stream.
    public var streamIdentifier: StreamIdentifier {
        get {
            target.identifier
        }
    }
    
    /// The group name of the persistent subscription.
    public var group: String {
        get {
            target.group
        }
    }
    
    /// Creates a persistent subscription for a specific stream.
    ///
    /// - Parameters:
    ///   - options: Configuration options for creating the subscription, defaulting to an empty configuration.
    /// - Throws: An error if the creation fails.
    public func create(options: CreateToStream.Options = .init()) async throws {
        let usecase: CreateToStream = .init(streamIdentifier: streamIdentifier, group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }

    /// Updates an existing persistent subscription for a specific stream.
    ///
    /// - Parameters:
    ///   - options: Configuration options for updating the subscription, defaulting to an empty configuration.
    /// - Throws: An error if the update fails.
    public func update(settings: PersistentSubscription.Settings, from cursor: RevisionCursor = .end) async throws {
        let usecase = UpdateToStream(streamIdentifier: streamIdentifier, group: group, options: .init(settings: settings).startFrom(cursor: cursor))
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }

    /// Deletes a persistent subscription for a specific stream.
    ///
    /// - Throws: An error if the deletion fails.
    public func delete() async throws {
        let usecase = Delete(stream: .specified(streamIdentifier), group: group)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }

    /// Subscribes to a persistent subscription for a specific stream.
    ///
    /// - Parameters:
    ///   - options: Configuration options for subscribing, defaulting to an empty configuration.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribe(options: Read.Options = .init()) async throws -> Subscription {
        let usecase = Read(streamSelection: .specified(streamIdentifier), group: group, options: options)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }

    /// Retrieves information about a persistent subscription for a specific stream.
    ///
    /// - Returns: A `PersistentSubscription.SubscriptionInfo` object containing subscription details.
    /// - Throws: An error if the information cannot be retrieved.
    public func getInfo() async throws -> PersistentSubscription.SubscriptionInfo {
        let usecase = GetInfo(stream: .specified(streamIdentifier), group: group)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }

    /// Replays parked messages for a persistent subscription targeting a specific stream.
    ///
    /// - Parameters:
    ///   - options: Configuration options for replaying parked messages, defaulting to an empty configuration.
    /// - Throws: An error if the replay operation fails.
    public func replayParkedMessages(options: ReplayParked.Options = .init()) async throws {
        let usecase = ReplayParked(streamSelection: .specified(streamIdentifier), group: group, options: options)
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
}

// MARK: - Generic Operations
/// Provides general operations for persistent subscriptions with an unspecified target.
extension PersistentSubscriptions where Target == PersistentSubscription.AnyTarget {
    /// Restarts the subsystem managing persistent subscriptions.
    ///
    /// - Throws: An error if the restart operation fails.
    @MainActor
    public func restartSubsystem() async throws {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Lists all persistent subscriptions for a specific stream.
    ///
    /// - Parameter streamIdentifier: The identifier of the stream to list subscriptions for.
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    public func listForStream(_ streamIdentifier: StreamIdentifier) async throws -> [PersistentSubscription.SubscriptionInfo] {
        let options: List.Options = try .listForStream(streamIdentifier)
        let usecase = List(options: options)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
    
    /// Lists all persistent subscriptions in the system.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    public func listAll() async throws -> [PersistentSubscription.SubscriptionInfo] {
        let options: List.Options = .listAllScriptions()
        let usecase = List(options: options)
        return try await usecase.perform(settings: clientSettings, callOptions: callOptions)
    }
}
