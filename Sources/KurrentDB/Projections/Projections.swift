//
//  Projections.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/10/17.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

/// A structure representing a projections service that interacts with a specific projection target.
///
/// This struct provides methods to manage projections, such as creating, updating, deleting, and retrieving
/// details or results, depending on the capabilities of the `Target` type.
///
/// - Parameter Target: The type conforming to `ProjectionTarget` that defines the projection's behavior.
public struct Projections<Target: ProjectionTarget>: GRPCConcreteService {
    /// The underlying gRPC client type used for communication.
    package typealias UnderlyingClient = EventStore_Client_Projections_Projections.Client<HTTP2ClientTransport.Posix>

    private(set) var settings: ClientSettings
    var callOptions: CallOptions
    let eventLoopGroup: EventLoopGroup
    private(set) var target: Target

    /// Initializes a new `Projections` instance with the specified target and settings.
    ///
    /// - Parameters:
    ///   - target: The projection target to operate on.
    ///   - settings: The client settings for gRPC communication.
    ///   - callOptions: The call options for gRPC requests. Defaults to `.defaults`.
    ///   - eventLoopGroup: The event loop group for asynchronous operations. Defaults to a singleton multi-threaded group.
    internal init(target: Target, settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Projections where Target: NameSpecifiable & ProjectionCreatable {
    /// Creates a continuous projection with the specified query and configuration.
    ///
    /// - Parameters:
    ///   - query: The query string defining the projection.
    ///   - configure: A closure to modify the `ContinuousCreate.Options` in-place. Throws if configuration fails.
    /// - Throws: An error if the creation process or configuration fails.
    public func createContinuous(query: String, configure: (inout ContinuousCreate.Options) throws -> Void = { _ in }) async throws {
        var options = ContinuousCreate.Options()
        try configure(&options)
        let usecase = ContinuousCreate(name: target.name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable {
    /// The name of the projection target.
    var name: String {
        target.name
    }
}

extension Projections where Target == AllProjectionTarget<ContinuousMode> {
    /// Retrieves a list of all continuous projection statistics.
    ///
    /// - Returns: An array of `Statistics.Detail` containing projection statistics.
    /// - Throws: An error if the operation fails.
    public func list() async throws -> [Statistics.Detail] {
        let usecase = Statistics(options: .listAll(mode: target.mode.mode))
        return try await usecase.perform(settings: settings, callOptions: callOptions).reduce(into: .init()) { partialResult, response in
            partialResult.append(response.detail)
        }
    }
}

extension Projections where Target == AllProjectionTarget<AnyMode> {
    /// Retrieves a list of all projection statistics for any mode.
    ///
    /// - Returns: An array of `Statistics.Detail` containing projection statistics.
    /// - Throws: An error if the operation fails.
    public func list() async throws -> [Statistics.Detail] {
        let usecase = Statistics(options: .listAll(mode: target.mode.mode))
        return try await usecase.perform(settings: settings, callOptions: callOptions).reduce(into: .init()) { partialResult, response in
            partialResult.append(response.detail)
        }
    }
}

extension Projections where Target: NameSpecifiable & ProjectionEnable {
    /// Enables the projection.
    ///
    /// - Throws: An error if enabling the projection fails.
    public func enable() async throws {
        let usecase = Enable(name: name, options: .init())
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionDisable {
    /// Disables the projection and writes a checkpoint.
    ///
    /// - Throws: An error if disabling the projection fails.
    public func disable() async throws {
        let options = Disable.Options().writeCheckpoint(enabled: true)
        let usecase = Disable(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
    
    /// Aborts the projection without writing a checkpoint.
    ///
    /// - Throws: An error if aborting the projection fails.
    public func abort() async throws {
        let options = Disable.Options().writeCheckpoint(enabled: false)
        let usecase = Disable(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionResetable {
    /// Resets the projection to its initial state.
    ///
    /// - Throws: An error if resetting the projection fails.
    public func reset() async throws {
        let usecase = Reset(name: name, options: .init())
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionDeletable {
    /// Deletes the projection with the specified configuration.
    ///
    /// - Parameter configure: A closure to modify the `Delete.Options` in-place. Defaults to no modifications.
    /// - Throws: An error if deletion or configuration fails.
    public func delete(configure: (inout Delete.Options) throws -> Void = { _ in }) async throws {
        var options = Delete.Options()
        try configure(&options)
        let usecase = Delete(name: name, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionUpdatable {
    /// Updates the projection with an optional query and configuration.
    ///
    /// - Parameters:
    ///   - query: An optional query string to update the projection. If `nil`, the query remains unchanged.
    ///   - configure: A closure to modify the `Update.Options` in-place.
    /// - Throws: An error if updating or configuration fails.
    public func update(query: String?, configure: (inout Update.Options) throws -> Void) async throws {
        var options = Update.Options()
        try configure(&options)
        let usecase = Update(name: name, query: query, options: options)
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension Projections where Target: NameSpecifiable & ProjectionDescribable {
    /// Retrieves detailed statistics for the projection.
    ///
    /// - Returns: An optional `Statistics.Detail` containing the projection's details, or `nil` if none exist.
    /// - Throws: An error if retrieving details fails.
    public func detail() async throws -> Statistics.Detail? {
        let usecase = Statistics(options: .specified(name: name))
        let response = try await usecase.perform(settings: settings, callOptions: callOptions).first { _ in true }
        return response?.detail
    }
}

extension Projections where Target: NameSpecifiable & ProjectionResulable {
    /// Retrieves the result of the projection decoded to a specified type.
    ///
    /// - Parameters:
    ///   - _: The type to decode the result into, conforming to `Decodable`.
    ///   - configure: A closure to modify the `Result.Options` in-place. Defaults to no modifications.
    /// - Returns: An optional decoded result of type `DecodeType`, or `nil` if decoding fails.
    /// - Throws: An error if the operation or decoding fails.
    public func result<DecodeType: Decodable>(of _: DecodeType.Type, configure: (inout Result.Options) throws -> Void = { _ in }) async throws -> DecodeType? {
        var options = Result.Options()
        try configure(&options)
        let usecase = Result(name: name, options: options)
        let response = try await usecase.perform(settings: settings, callOptions: callOptions)
        return try response.decode(to: DecodeType.self)
    }
    
    /// Retrieves the state of the projection decoded to a specified type.
    ///
    /// - Parameters:
    ///   - _: The type to decode the state into, conforming to `Decodable`.
    ///   - configure: A closure to modify the `State.Options` in-place. Defaults to no modifications.
    /// - Returns: An optional decoded state of type `DecodeType`, or `nil` if decoding fails.
    /// - Throws: An error if the operation or decoding fails.
    public func state<DecodeType: Decodable>(of _: DecodeType.Type, configure: (inout State.Options) throws -> Void = { _ in }) async throws -> DecodeType? {
        var options = State.Options()
        try configure(&options)
        let usecase = State(name: name, options: options)
        let response = try await usecase.perform(settings: settings, callOptions: callOptions)
        return try response.decode(to: DecodeType.self)
    }
}
