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
/// - Parameter Target: The type conforming to `ProjectionsTarget` that defines the projection's behavior.
public actor Projections<Target: ProjectionsTarget>: GRPCConcreteService {
    /// The underlying gRPC client type used for communication.
    package typealias UnderlyingClient = EventStore_Client_Projections_Projections.Client<HTTP2ClientTransport.Posix>

    private(set) var selector: NodeSelector
    var callOptions: CallOptions
    let eventLoopGroup: EventLoopGroup
    private(set) var target: Target

    package let serviceName: String = "event_store.client.projections.projections"

    /// Initializes a new `Projections` instance with the specified target and settings.
    ///
    /// - Parameters:
    ///   - target: The projection target to operate on.
    ///   - settings: The client settings for gRPC communication.
    ///   - callOptions: The call options for gRPC requests. Defaults to `.defaults`.
    ///   - eventLoopGroup: The event loop group for asynchronous operations. Defaults to a singleton multi-threaded group.
    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

// MARK: - enable

extension Projections where Target: ProjectionControlable {
    /// Enables the projection.
    ///
    /// - Throws: An error if enabling the projection fails.
    public func enable() async throws(KurrentError) {
        let usecase = Enable(name: target.name, options: .init())
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - disable / abort

extension Projections where Target: ProjectionControlable {
    /// Disables the projection and writes a checkpoint.
    ///
    /// - Throws: An error if disabling the projection fails.
    public func disable() async throws(KurrentError) {
        let options = Disable.Options().writeCheckpoint(enabled: true)
        let usecase = Disable(name: target.name, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Aborts the projection without writing a checkpoint.
    ///
    /// - Throws: An error if aborting the projection fails.
    public func abort() async throws(KurrentError) {
        let options = Disable.Options().writeCheckpoint(enabled: false)
        let usecase = Disable(name: target.name, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - reset

extension Projections where Target: ProjectionControlable {
    /// Resets the projection to its initial state.
    ///
    /// - Throws: An error if resetting the projection fails.
    public func reset() async throws(KurrentError) {
        let usecase = Reset(name: target.name, options: .init())
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - delete

extension Projections where Target: ProjectionControlable {
    /// Deletes the projection with the specified options.
    ///
    /// - Parameter options: The options for deleting the projection. Defaults to an empty configuration.
    /// - Throws: An error if deletion fails.
    public func delete(options: Delete.Options = .init()) async throws(KurrentError) {
        let usecase = Delete(name: target.name, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - update

extension Projections where Target: ProjectionControlable {
    /// Updates the projection with an optional query and options.
    ///
    /// - Parameters:
    ///   - query: An optional query string to update the projection. If `nil`, the query remains unchanged.
    ///   - options: The options for updating the projection. Defaults to an empty configuration.
    /// - Throws: An error if updating fails.
    public func update(query: String?, options: Update.Options = .init()) async throws(KurrentError) {
        let usecase = Update(name: target.name, query: query, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - detail

extension Projections where Target: ProjectionControlable {
    /// Retrieves detailed statistics for the projection.
    ///
    /// - Returns: An optional `Statistics.Detail` containing the projection's details, or `nil` if none exist.
    /// - Throws: An error if retrieving details fails.
    public func detail() async throws(KurrentError) -> Statistics.Detail? {
        let usecase = Statistics(options: .specified(name: target.name))
        let response = try await usecase.perform(selector: selector, callOptions: callOptions)
        do {
            let result = try await response.first { _ in true }
            return result?.detail
        } catch {
            throw .internalClientError(reason: "The error happened while get the first detail from resposes, cause: \(error)")
        }
    }
}

// MARK: - get result / state

extension Projections where Target: ProjectionControlable {
    /// Retrieves the result of the projection decoded to a specified type.
    ///
    /// - Parameters:
    ///   - _: The type to decode the result into, conforming to `Decodable`.
    ///   - options: The options for retrieving the result. Defaults to an empty configuration.
    /// - Returns: An optional decoded result of type `DecodeType`, or `nil` if decoding fails.
    /// - Throws: An error if the operation or decoding fails.
    public func result<DecodeType: Decodable>(of _: DecodeType.Type, options: Result.Options = .init()) async throws(KurrentError) -> DecodeType? {
        let usecase = Result(name: target.name, options: options)
        let response = try await usecase.perform(selector: selector, callOptions: callOptions)
        do {
            return try response.decode(to: DecodeType.self)
        } catch let error as DecodingError {
            throw .decodingError(cause: error)
        } catch {
            throw .internalClientError(reason: "Decoding state failed, cause: \(error)")
        }
    }

    /// Retrieves the state of the projection decoded to a specified type.
    ///
    /// - Parameters:
    ///   - _: The type to decode the state into, conforming to `Decodable`.
    ///   - options: The options for retrieving the state. Defaults to an empty configuration.
    /// - Returns: An optional decoded state of type `DecodeType`, or `nil` if decoding fails.
    /// - Throws: An error if the operation or decoding fails.
    public func state<DecodeType: Decodable>(of _: DecodeType.Type, options: State.Options = .init()) async throws(KurrentError) -> DecodeType? {
        do {
            let usecase = State(name: target.name, options: options)
            let response = try await usecase.perform(selector: selector, callOptions: callOptions)
            return try response.decode(to: DecodeType.self)
        } catch let error as KurrentError {
            throw error
        } catch let error as DecodingError {
            throw .decodingError(cause: error)
        } catch {
            throw .internalClientError(reason: "Decoding state failed, cause: \(error)")
        }
    }
}

extension Projections {
    /// Retrieves a list of all continuous projection statistics.
    ///
    /// - Returns: An array of `Statistics.Detail` containing projection statistics.
    /// - Throws: An error if the operation fails.
    public func list(mode: Projection.Mode) async throws(KurrentError) -> [Statistics.Detail] {
        let usecase = Statistics(options: .listAll(mode: mode))
        let response = try await usecase.perform(selector: selector, callOptions: callOptions)
        do {
            return try await response.reduce(into: .init()) { partialResult, response in
                partialResult.append(response.detail)
            }
        } catch {
            throw .internalClientError(reason: "The error happened while get the list of projections, cause: \(error)")
        }
    }
}

extension Projections {
    /// Retrieves a list of all projection statistics for any mode.
    ///
    /// - Returns: An array of `Statistics.Detail` containing projection statistics.
    /// - Throws: An error if the operation fails.
    public func list(for mode: some ProjectionMode) async throws(KurrentError) -> [Statistics.Detail] {
        let usecase = Statistics(options: .listAll(mode: mode.mode))
        let response = try await usecase.perform(selector: selector, callOptions: callOptions)
        do {
            return try await response.reduce(into: .init()) { partialResult, response in
                partialResult.append(response.detail)
            }
        } catch {
            throw .internalClientError(reason: "The error happened while get the list of projections, cause: \(error)")
        }
    }
}
