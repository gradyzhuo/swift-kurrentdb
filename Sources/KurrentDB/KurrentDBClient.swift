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
/// - ``setStreamMetadata(on:metadata:expectedRevision:)``
/// - ``getStreamMetadata(on:)``
/// - ``appendStream(on:events:configure:)``
/// - ``readAllStreams(startFrom:configure:)``
/// - ``readStream(on:startFrom:configure:)``
/// - ``subscribeAllStreams(startFrom:configure:)``
/// - ``subscribeStream(on:startFrom:configure:)``
/// - ``deleteStream(on:configure:)``
/// - ``tombstoneStream(on:configure:)``
/// - ``copyStream(_:toNewStream:)``
///
/// #### Persistent Subscription Operations
/// - ``createPersistentSubscription(to:groupName:startFrom:configure:)``
/// - ``createPersistentSubscriptionToAllStream(groupName:startFrom:configure:)``
/// - ``deletePersistentSubscription(to:groupName:)``
/// - ``deletePersistentSubscriptionToAllStream(groupName:)``
/// - ``listPersistentSubscriptions(to:)``
/// - ``listPersistentSubscriptionsToAllStream()``
/// - ``listAllPersistentSubscription()``
///
/// #### Projection Operations
/// - ``createContinuousProjection(name:query:configure:)``
/// - ``updateProjection(name:query:configure:)``
/// - ``disableProjection(name:)``
/// - ``abortProjection(name:)``
/// - ``deleteProjection(name:configure:)``
/// - ``resetProjection(name:)``
/// - ``getProjectionResult(name:configure:)``
/// - ``getProjectionState(name:configure:)``
/// - ``getProjectionDetail(name:)``
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

/// Provides access to core service instances.
extension KurrentDBClient {
    /// Creates a `Streams` instance for a specific target.
    ///
    /// - Parameter target: The stream target (e.g., `SpecifiedStream`, `AllStreams`, or `ProjectionStream`).
    /// - Returns: A `Streams` instance configured with the client's settings.
    private func streams<Target: StreamTarget>(of target: Target) -> Streams<Target> {
        return .init(target: target, settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// The persistent subscriptions service for all streams.
    private var persistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        return .init(target: .all, settings: settings, callOptions: defaultCallOptions)
    }
    
    /// Creates a `Projections` instance for all projections with a specific mode.
    ///
    /// - Parameter mode: The projection mode (e.g., `ContinuousMode` or `AnyMode`).
    /// - Returns: A `Projections` instance configured with the client's settings.
    private func projections<Mode: ProjectionMode>(all mode: Mode) -> Projections<AllProjectionTarget<Mode>> {
        .init(target: .init(mode: mode), settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// Creates a `Projections` instance for a named projection.
    ///
    /// - Parameter name: The name of the projection.
    /// - Returns: A `Projections` instance configured with the client's settings.
    private func projections(name: String) -> Projections<String> {
        .init(target: name, settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    /// Creates a `Projections` instance for a system projection.
    ///
    /// - Parameter predefined: The predefined system projection type (e.g., `.byCategory`).
    /// - Returns: A `Projections` instance configured with the client's settings.
    private func projections(system predefined: SystemProjectionTarget.Predefined) -> Projections<SystemProjectionTarget> {
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
    /// Sets metadata for a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - metadata: The metadata to associate with the stream.
    ///   - expectedRevision: The expected revision of the stream for concurrency control, defaulting to `.any`.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    /// - Throws: An error if the metadata cannot be set.
    @discardableResult
    public func setStreamMetadata(on streamIdentifier: StreamIdentifier, metadata: StreamMetadata, expectedRevision: StreamRevision = .any) async throws -> Streams<SpecifiedStream>.Append.Response {
        try await streams(of: .specified(streamIdentifier))
            .setMetadata(metadata: metadata, expectedRevision: expectedRevision)
    }

    /// Retrieves metadata for a specific stream.
    ///
    /// - Parameter streamIdentifier: The identifier of the target stream.
    /// - Returns: The `StreamMetadata` if available, otherwise `nil`.
    /// - Throws: An error if the metadata cannot be retrieved.
    public func getStreamMetadata(on streamIdentifier: StreamIdentifier) async throws -> StreamMetadata? {
        return try await streams(of: .specified(streamIdentifier)).getMetadata()
    }
    
    /// Appends events to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - events: An array of events to append.
    ///   - configure: A closure to customize the append options, defaulting to no modifications.
    /// - Returns: An `Append.Response` indicating the result.
    /// - Throws: An error if the append operation fails.
    @discardableResult
    public func appendStream(on streamIdentifier: StreamIdentifier, events: [EventData], configure: (Streams<SpecifiedStream>.Append.Options) -> Streams<SpecifiedStream>.Append.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Append.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).append(events: events, options: options)
    }
    
    /// Reads events from all streams.
    ///
    /// - Parameters:
    ///   - cursor: The starting position for reading, defaulting to `.start`.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    /// - Throws: An error if the read operation fails.
    public func readAllStreams(startFrom cursor: PositionCursor = .start, configure: (Streams<AllStreams>.ReadAll.Options) -> Streams<AllStreams>.ReadAll.Options = { $0 }) async throws -> Streams<AllStreams>.ReadAll.Responses {
        let options = configure(.init())
        return try await streams(of: .all).read(startFrom: cursor, options: options)
    }
    
    /// Reads events from a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - cursor: The starting revision for reading, defaulting to `.start`.
    ///   - configure: A closure to customize the read options, defaulting to no modifications.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    /// - Throws: An error if the read operation fails.
    public func readStream(on streamIdentifier: StreamIdentifier, startFrom cursor: RevisionCursor = .start, configure: (Streams<SpecifiedStream>.Read.Options) -> Streams<SpecifiedStream>.Read.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Read.Responses {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).read(startFrom: cursor, options: options)
    }
    
    /// Subscribes to all streams.
    ///
    /// - Parameters:
    ///   - cursor: The starting position for the subscription, defaulting to `.start`.
    ///   - configure: A closure to customize the subscription options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribeAllStreams(startFrom cursor: PositionCursor = .start, configure: (Streams<AllStreams>.SubscribeAll.Options) -> Streams<AllStreams>.SubscribeAll.Options = { $0 }) async throws -> Streams<AllStreams>.Subscription {
        let options = configure(.init())
        return try await streams(of: .all).subscribe(startFrom: cursor, options: options)
    }
    
    /// Subscribes to a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - cursor: The starting revision for the subscription, defaulting to `.end`.
    ///   - configure: A closure to customize the subscription options, defaulting to no modifications.
    /// - Returns: A `Subscription` instance for receiving events.
    /// - Throws: An error if the subscription fails.
    public func subscribeStream(on streamIdentifier: StreamIdentifier, startFrom cursor: RevisionCursor = .end, configure: (Streams<SpecifiedStream>.Subscribe.Options) -> Streams<SpecifiedStream>.Subscribe.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Subscription {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).subscribe(startFrom: cursor, options: options)
    }
    
    /// Deletes a specific stream.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - configure: A closure to customize the delete options, defaulting to no modifications.
    /// - Returns: A `Delete.Response` indicating the result.
    /// - Throws: An error if the delete operation fails.
    @discardableResult
    public func deleteStream(on streamIdentifier: StreamIdentifier, configure: (Streams<SpecifiedStream>.Delete.Options) -> Streams<SpecifiedStream>.Delete.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Delete.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).delete(options: options)
    }
    
    /// Tombstones a specific stream, marking it as permanently deleted.
    ///
    /// - Parameters:
    ///   - streamIdentifier: The identifier of the target stream.
    ///   - configure: A closure to customize the tombstone options, defaulting to no modifications.
    /// - Returns: A `Tombstone.Response` indicating the result.
    /// - Throws: An error if the tombstone operation fails.
    @discardableResult
    public func tombstoneStream(on streamIdentifier: StreamIdentifier, configure: (Streams<SpecifiedStream>.Tombstone.Options) -> Streams<SpecifiedStream>.Tombstone.Options = { $0 }) async throws -> Streams<SpecifiedStream>.Tombstone.Response {
        let options = configure(.init())
        return try await streams(of: .specified(streamIdentifier)).tombstone(options: options)
    }
    
    /// Copies events from one stream to a new stream.
    ///
    /// - Parameters:
    ///   - fromIdentifier: The identifier of the source stream.
    ///   - newIdentifier: The identifier of the destination stream.
    /// - Throws: An error if the copy operation fails.
    public func copyStream(_ fromIdentifier: StreamIdentifier, toNewStream newIdentifier: StreamIdentifier) async throws {
        let readResponses = try await streams(of: .specified(fromIdentifier)).read(options: .init().resolveLinks())
        let events = try await readResponses.reduce(into: [EventData]()) { partialResult, response in
            let recordedEvent = try response.event.record
            let event = EventData(like: recordedEvent)
            partialResult.append(event)
        }
        try await streams(of: .specified(newIdentifier)).append(events: events, options: .init().revision(expected: .noStream))
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
    ///   - configure: A closure to customize the creation options, defaulting to no modifications.
    /// - Throws: An error if the creation fails.
    public func createPersistentSubscription(to streamIdentifier: StreamIdentifier, groupName: String, startFrom cursor: RevisionCursor = .end, configure: (PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create(startFrom: cursor, options: options)
    }
    
    /// Creates a persistent subscription to all streams.
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group.
    ///   - cursor: The starting position for the subscription, defaulting to `.start`.
    ///   - configure: A closure to customize the creation options, defaulting to no modifications.
    /// - Throws: An error if the creation fails.
    public func createPersistentSubscriptionToAllStream(groupName: String, startFrom cursor: PositionCursor = .start, configure: (PersistentSubscriptions<PersistentSubscription.AllStream>.Create.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.Create.Options = { $0 }) async throws {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create(startFrom: cursor, options: options)
    }
    
    public func subscribePersistentSubscription(to streamIdentifier: StreamIdentifier, groupName: String, configure: (PersistentSubscriptions<PersistentSubscription.Specified>.ReadOptions) -> PersistentSubscriptions<PersistentSubscription.Specified>.ReadOptions = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamIdentifier))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }
    
    public func subscribePersistentSubscriptionToAllStreams(groupName: String, configure: (PersistentSubscriptions<PersistentSubscription.AllStream>.ReadOptions) -> PersistentSubscriptions<PersistentSubscription.AllStream>.ReadOptions = { $0 }) async throws -> PersistentSubscriptions<PersistentSubscription.AllStream>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .all)
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
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
    
    public func restartPersistentSubscriptionSubsystem() async throws {
        try await persistentSubscriptions.restartSubsystem()
    }
}

/// Provides methods for projection operations.
extension KurrentDBClient {
    /// Creates a continuous projection with a specified name and query.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to create.
    ///   - query: The query defining the projection's logic.
    ///   - configure: A closure to customize the creation options, defaulting to no modifications.
    /// - Throws: An error if the creation fails.
    public func createContinuousProjection(name: String, query: String, configure: (Projections<String>.ContinuousCreate.Options) -> Projections<String>.ContinuousCreate.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).createContinuous(query: query, options: options)
    }
    
    /// Updates an existing projection with a new query.
    ///
    /// - Parameters:
    ///   - name: The name of the projection to update.
    ///   - query: The updated query for the projection.
    ///   - configure: A closure to customize the update options, defaulting to no modifications.
    /// - Throws: An error if the update fails.
    public func updateProjection(name: String, query: String, configure: (Projections<String>.Update.Options) -> Projections<String>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(name: name).update(query: query, options: options)
    }
    
    /// Disables a projection.
    ///
    /// - Parameter name: The name of the projection to disable.
    /// - Throws: An error if the disable operation fails.
    public func enableProjection(name: String) async throws {
        try await projections(name: name).enable()
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
    ///   - configure: A closure to customize the delete options, defaulting to no modifications.
    /// - Throws: An error if the delete operation fails.
    public func deleteProjection(name: String, configure: (Projections<String>.Delete.Options) -> Projections<String>.Delete.Options = { $0 }) async throws {
        let options = configure(.init())
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
    ///   - configure: A closure to customize the result options, defaulting to no modifications.
    /// - Returns: The decoded result of type `T`, or `nil` if no result is available.
    /// - Throws: An error if the retrieval or decoding fails.
    public func getProjectionResult<T: Decodable>(of: T.Type = T.self, name: String, configure: (Projections<String>.Result.Options) -> Projections<String>.Result.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).result(of: T.self, options: options)
    }
    
    /// Retrieves the state of a projection.
    ///
    /// - Parameters:
    ///   - name: The name of the projection.
    ///   - configure: A closure to customize the state options, defaulting to no modifications.
    /// - Returns: The decoded state of type `T`, or `nil` if no state is available.
    /// - Throws: An error if the retrieval or decoding fails.
    public func getProjectionState<T: Decodable>(of: T.Type = T.self, name: String, configure: (Projections<String>.State.Options) -> Projections<String>.State.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(name: name).state(of: T.self, options: options)
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
