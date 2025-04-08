//
//  KurrentDBClient.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/1/27.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2
import NIO
import NIOSSL

/// A client encapsulating gRPC use cases for EventStoreDB.
///
/// `KurrentDBClient` provides a high-level interface to interact with EventStoreDB, offering access to
/// streams, persistent subscriptions, projections, users, monitoring, and operations. It conforms to
/// `Sendable` and `Buildable` for safe concurrency and flexible construction.
///
/// - Note: This client relies on **gRPC** and requires a valid `ClientSettings` configuration.
///
/// ### Topics
/// #### Stream Operations
/// - ``streams(of:)``
/// - ``appendStream(to:events:options:)``
/// - ``readAllStreams(from:options:)``
/// - ``readStream(to:from:options:)``
/// - ``subscribeAllStreams(from:options:)``
/// - ``subscribeStream(to:from:options:)``
/// - ``deleteStream(to:options:)``
/// - ``tombstoneStream(to:options:)``
///
/// #### Persistent Subscription Operations
/// - ``persistentSubscriptions``
/// - ``createPersistentSubscription(to:groupName:startFrom:options:)``
/// - ``createPersistentSubscriptionToAllStream(groupName:startFrom:options:)``
/// - ``deletePersistentSubscription(to:groupName:)``
/// - ``deletePersistentSubscriptionToAllStream(groupName:)``
/// - ``listPersistentSubscriptions(to:)``
/// - ``listPersistentSubscriptionsToAllStream()``
/// - ``listAllPersistentSubscription()``
///
/// #### Projection Operations
/// - ``projections(all:)``
/// - ``projections(name:)``
/// - ``projections(system:)``
/// - ``restartProjectionSubsystem()``
///
/// #### User Management
/// - ``users``
///
/// #### Monitoring
/// - ``monitoring``
///
/// #### Server Operations
/// - ``operations``
/// - ``startScavenge(threadCount:startFromChunk:)``
/// - ``stopScavenge(scavengeId:)``
public struct KurrentDBClient: Sendable, Buildable {
    /// The default gRPC call options for all operations.
    public private(set) var defaultCallOptions: CallOptions
    
    /// The client settings for establishing a gRPC connection.
    public private(set) var settings: ClientSettings
    
    /// The event loop group for asynchronous tasks.
    package let group: EventLoopGroup

    /// Initializes a `KurrentDBClient` with settings and thread configuration.
    ///
    /// - Parameters:
    ///   - settings: The client settings encapsulating configuration details.
    ///   - numberOfThreads: The number of threads for the `EventLoopGroup`, defaulting to 1.
    ///   - defaultCallOptions: The default call options for all gRPC calls, defaulting to `.defaults`.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        group = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }
}

/// Provides access to stream-related operations.
extension KurrentDBClient {
    /// Creates a `Streams` instance for a specific target.
    ///
    /// - Parameter target: The stream target (e.g., `SpecifiedStream` or `AllStreams`).
    /// - Returns: A `Streams` instance configured with the client's settings.
    public func streams<Target: StreamTarget>(of target: Target) -> Streams<Target> {
        return .init(target: target, settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The persistent subscriptions service for all streams.
    public var persistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        return .init(target: .all, settings: settings, callOptions: defaultCallOptions)
    }
    
    /// Creates a `Projections` instance for all projections with a specific mode.
    ///
    /// - Parameter mode: The projection mode (e.g., `ContinuousMode`).
    /// - Returns: A `Projections` instance configured with the client's settings.
    public func projections<Mode: ProjectionMode>(all mode: Mode) -> Projections<AllProjectionTarget<Mode>> {
        .init(target: .init(mode: mode), settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// Creates a `Projections` instance for a named projection.
    ///
    /// - Parameter name: The name of the projection.
    /// - Returns: A `Projections` instance configured with the client's settings.
    public func projections(name: String) -> Projections<String> {
        .init(target: name, settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// Creates a `Projections` instance for a system projection.
    ///
    /// - Parameter predefined: The predefined system projection type (e.g., `.byCategory`).
    /// - Returns: A `Projections` instance configured with the client's settings.
    public func projections(system predefined: SystemProjectionTarget.Predefined) -> Projections<SystemProjectionTarget> {
        .init(target: .init(predefined: predefined), settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The user management service instance.
    public var users: Users {
        .init(settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The monitoring service instance.
    public var monitoring: Monitoring {
        .init(settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The operations service instance.
    public var operations: Operations {
        .init(settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
}

/// Provides convenience methods for stream operations.
extension KurrentDBClient {
    /// Appends events to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - events: The array of events to append.
    ///   - options: Configuration options for the append operation.
    /// - Returns: An `Append.Response` indicating the result.
    /// - Throws: An error if the append operation fails.
    public func appendStream(to streamIdentifier: StreamIdentifier, events: [EventData], options: Streams<SpecifiedStream>.Append.Options) async throws -> Streams<SpecifiedStream>.Append.Response {
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }
    
    /// Reads events from all streams.
    ///
    /// - Parameters:
    ///   - cursor: The starting position for reading.
    ///   - options: Configuration options for the read operation.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    /// - Throws: An error if the read operation fails.
    public func readAllStreams(from cursor: PositionCursor, options: Streams<AllStreams>.ReadAll.Options) async throws -> Streams<AllStreams>.ReadAll.Responses {
        return try await streams(of: .all).read(from: cursor, options: options)
    }
    
    /// Reads events from a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - cursor: The starting revision for reading.
    ///   - options: Configuration options for the read operation.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    /// - Throws: An error if the read operation fails.
    public func readStream(to streamIdentifier: StreamIdentifier, from cursor: RevisionCursor, options: Streams<SpecifiedStream>.Read.Options) async throws -> Streams<SpecifiedStream>.Read.Responses {
        return try await streams(of: .specified(streamIdentifier)).read(from: cursor, options: options)
    }
    
    /// Subscribes to all streams.
    ///
    /// - Parameters:
    ///   - cursor: The starting position for the subscription.
    ///   - options: Configuration options for the subscription.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribeAllStreams(from cursor: PositionCursor, options: Streams<AllStreams>.SubscribeAll.Options) async throws -> Streams<AllStreams>.Subscription {
        return try await streams(of: .all).subscribe(from: cursor, options: options)
    }
    
    /// Subscribes to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - cursor: The starting revision for the subscription.
    ///   - options: Configuration options for the subscription.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribeStream(to streamIdentifier: StreamIdentifier, from cursor: RevisionCursor, options: Streams<SpecifiedStream>.Subscribe.Options) async throws -> Streams<SpecifiedStream>.Subscription {
        return try await streams(of: .specified(streamIdentifier)).subscribe(from: cursor, options: options)
    }
    
    /// Deletes a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - options: Configuration options for the delete operation.
    /// - Returns: A `Delete.Response` indicating the result.
    /// - Throws: An error if the delete operation fails.
    @discardableResult
    public func deleteStream(to streamIdentifier: StreamIdentifier, options: Streams<SpecifiedStream>.Delete.Options) async throws -> Streams<SpecifiedStream>.Delete.Response {
        return try await streams(of: .specified(streamIdentifier)).delete(options: options)
    }
    
    /// Tombstones a specific stream (marks it as permanently deleted).
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - options: Configuration options for the tombstone operation.
    ///   - Returns: A `Tombstone.Response` indicating the result.
    /// - Throws: An error if the tombstone operation fails.
    @discardableResult
    public func tombstoneStream(to streamIdentifier: StreamIdentifier, options: Streams<SpecifiedStream>.Tombstone.Options) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        return try await streams(of: .specified(streamIdentifier)).tombstone(options: options)
    }
}

extension KurrentDBClient {
    public func copyStream(newStreamIdentifier: StreamIdentifier, fromStream fromIdentifier: StreamIdentifier) async throws {
        try await streams(of: .specified(fromIdentifier)).copy(to: newStreamIdentifier)
    }
}

/// Provides convenience methods for persistent subscription operations.
extension KurrentDBClient {
    /// Creates a persistent subscription to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - options: Configuration options for creating the subscription.
    /// - Throws: An error if the creation fails.
    public func createPersistentSubscription(to streamIdentifier: StreamIdentifier, groupName: String, startFrom cursor: RevisionCursor = .end, options: PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options) async throws {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create(startFrom: cursor, options: options)
    }
    
    /// Creates a persistent subscription to all streams.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting position for the subscription.
    ///   - options: Configuration options for creating the subscription.
    /// - Throws: An error if the creation fails.
    public func createPersistentSubscriptionToAllStream(groupName: String, startFrom cursor: PositionCursor, options: PersistentSubscriptions<PersistentSubscription.AllStream>.Create.Options) async throws {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create(startFrom: cursor, options: options)
    }
    
    /// Deletes a persistent subscription for a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    public func deletePersistentSubscription(to streamIdentifier: StreamIdentifier, groupName: String) async throws {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .delete()
    }
    
    /// Deletes a persistent subscription for all streams.
    ///
    /// - Parameter groupName: The name of the subscription group.
    /// - Throws: An error if the deletion fails.
    public func deletePersistentSubscriptionToAllStream(groupName: String) async throws {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .delete()
    }
    
    /// Lists persistent subscriptions for a specific stream.
    ///
    /// - Parameter streamIdentifier: The identifier of the target stream.
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    public func listPersistentSubscriptions(to streamIdentifier: StreamIdentifier) async throws -> [PersistentSubscription.SubscriptionInfo] {
        return try await persistentSubscriptions.list(for: .stream(streamIdentifier))
    }
    
    /// Lists persistent subscriptions for all streams.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    public func listPersistentSubscriptionsToAllStream() async throws -> [PersistentSubscription.SubscriptionInfo] {
        return try await persistentSubscriptions.list(for: .stream(.all))
    }
    
    /// Lists all persistent subscriptions in the system.
    ///
    /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` objects.
    /// - Throws: An error if the list operation fails.
    public func listAllPersistentSubscription() async throws -> [PersistentSubscription.SubscriptionInfo] {
        return try await persistentSubscriptions.list(for: .allSubscriptions)
    }
}

/// Provides methods for projection subsystem operations.
extension KurrentDBClient {
    
    /// Creates a continuous projection with a specified name and query.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to create.
    ///   - query: The query defining the projection's logic.
    ///   - options: Configuration options for creating the continuous projection, defaulting to an empty configuration.
    /// - Throws: An error if the creation fails.
    public func createContinuousProjection(name: String, query: String, options: Projections<String>.ContinuousCreate.Options = .init()) async throws {
        try await projections(name: name).createContinuous(query: query, options: options)
    }
    
    /// Updates an existing projection with a new query.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to update.
    ///   - query: The updated query for the projection.
    ///   - options: Configuration options for updating the projection, defaulting to an empty configuration.
    /// - Throws: An error if the update fails.
    public func updateProjection(name: String, query: String, options: Projections<String>.Update.Options = .init()) async throws {
        try await projections(name: name).update(query: query, options: options)
    }
    
    /// Disables a projection.
    ///
    /// - Parameter name: The name of the projection to disable.
    /// - Throws: An error if the disable operation fails.
    public func disableProjection(name: String) async throws {
        try await projections(name: name).disable()
    }
    
    /// Aborts a projection.
    ///
    /// - Parameter name: The name of the projection to abort.
    /// - Throws: An error if the abort operation fails.
    public func abortProjection(name: String) async throws {
        try await projections(name: name).abort()
    }
    
    /// Deletes a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to delete.
    ///   - options: Configuration options for deleting the projection, defaulting to an empty configuration.
    /// - Throws: An error if the delete operation fails.
    public func deleteProjection(name: String, options: Projections<String>.Delete.Options = .init()) async throws {
        try await projections(name: name).delete(options: options)
    }
    
    /// Resets a projection to its initial state.
    ///
    /// - Parameter name: The name of the projection to reset.
    /// - Throws: An error if the reset operation fails.
    public func resetProjection(name: String) async throws {
        try await projections(name: name).reset()
    }

    /// Retrieves the result of a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - options: Configuration options for retrieving the result, defaulting to an empty configuration.
    /// - Returns: The decoded result of type `T`, or `nil` if no result is available.
    /// - Throws: An error if the retrieval or decoding fails.
    public func getProjectionResult<T: Decodable>(name: String, options: Projections<String>.Result.Options = .init()) async throws -> T? {
        try await projections(name: name).result(of: T.self, options: options)
    }
    
    /// Retrieves the state of a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - options: Configuration options for retrieving the state, defaulting to an empty configuration.
    /// - Returns: The decoded state of type `T`, or `nil` if no state is available.
    /// - Throws: An error if the retrieval or decoding fails.
    public func getProjectionState<T: Decodable>(name: String, options: Projections<String>.State.Options = .init()) async throws -> T? {
        try await projections(name: name).state(of: T.self, options: options)
    }
    
    /// Retrieves detailed statistics for a projection.
    ///
    /// - Parameter name: The name of the projection.
    /// - Returns: A `Projections<String>.Statistics.Detail` object if available, otherwise `nil`.
    /// - Throws: An error if the retrieval fails.
    public func getProjectionDetail(name: String) async throws -> Projections<String>.Statistics.Detail? {
        return try await projections(name: name).detail()
    }
    
    /// Restarts the projection subsystem.
    ///
    /// - Throws: A `KurrentError` if the restart operation fails.
    public func restartProjectionSubsystem() async throws(KurrentError) {
        let usecase = Projections<AllProjectionTarget<AnyMode>>.RestartSubsystem()
        _ = try await usecase.perform(settings: settings, callOptions: defaultCallOptions)
    }
}

/// Provides methods for server operations.
extension KurrentDBClient {
    /// Starts a scavenge operation to reclaim disk space.
    ///
    /// - Parameters:
    ///   - threadCount: The number of threads to use for the scavenge operation.
    ///   - startFromChunk: The chunk number from which to start scavenging.
    /// - Returns: An `Operations.ScavengeResponse` containing details about the operation.
    /// - Throws: An error if the scavenge operation fails.
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> Operations.ScavengeResponse {
        return try await operations.startScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
    }

    /// Stops an ongoing scavenge operation.
    ///
    /// - Parameter scavengeId: The identifier of the scavenge operation to stop.
    /// - Returns: An `Operations.ScavengeResponse` indicating the result.
    /// - Throws: An error if the scavenge operation cannot be stopped.
    public func stopScavenge(scavengeId: String) async throws -> Operations.ScavengeResponse {
        return try await operations.stopScavenge(scavengeId: scavengeId)
    }
}
