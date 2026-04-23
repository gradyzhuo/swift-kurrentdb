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

/// Projections service scoped to a specific ``ProjectionsTarget``.
///
/// Obtain an instance via `KurrentDBClient.projections(of:)` or one of its convenience overloads:
///
/// ```swift
/// let projections = client.projections(of: .continuous(name: "order-stats"))
/// try await projections.enable()
/// ```
public final class Projections<Target: ProjectionsTarget>: GRPCConcreteService {
    /// The underlying gRPC client type used for communication.
    package typealias UnderlyingClient = EventStore_Client_Projections_Projections.Client<HTTP2ClientTransport.Posix>

    internal let selector: NodeSelector
    internal let callOptions: CallOptions
    internal let eventLoopGroup: EventLoopGroup
    /// Target that scopes and constrains the available projection operations.
    public let target: Target

    package let serviceName: String = "event_store.client.projections.projections"

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
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func enable() async throws(KurrentError) {
        let usecase = Enable(name: target.name, options: .init())
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - disable / abort

extension Projections where Target: ProjectionControlable {
    /// Stops the projection and writes a checkpoint before halting.
    ///
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func disable() async throws(KurrentError) {
        var options = Disable.Options()
        options.writeCheckpoint = true
        let usecase = Disable(name: target.name, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }

    /// Stops the projection immediately without writing a checkpoint.
    ///
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func abort() async throws(KurrentError) {
        var options = Disable.Options()
        options.writeCheckpoint = false
        let usecase = Disable(name: target.name, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - reset

extension Projections where Target: ProjectionControlable {
    /// Resets the projection to its initial state, discarding all accumulated state.
    ///
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func reset() async throws(KurrentError) {
        let usecase = Reset(name: target.name, options: .init())
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - delete

extension Projections where Target: ProjectionControlable {
    /// Deletes the projection from the server.
    ///
    /// - Parameter configure: Closure to customise delete options such as whether to delete emitted streams.
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func delete(configure: @Sendable (inout Delete.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = Delete.Options()
        configure(&options)
        let usecase = Delete(name: target.name, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - update

extension Projections where Target: ProjectionControlable {
    /// Updates the projection's query and options on the server.
    ///
    /// - Parameters:
    ///   - query: Replacement query string, or `nil` to leave the existing query unchanged.
    ///   - configure: Closure to customise update options such as emit settings.
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func update(query: String?, configure: @Sendable (inout Update.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = Update.Options()
        configure(&options)
        let usecase = Update(name: target.name, query: query, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

// MARK: - detail

extension Projections where Target: ProjectionControlable {
    /// Fetches the current runtime statistics for the projection.
    ///
    /// - Returns: A `Projection.Detail` snapshot, or `nil` if the server returns no statistics.
    /// - Throws: `KurrentError` if the request fails or the response cannot be read.
    public func detail() async throws(KurrentError) -> Projection.Detail? {
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
    /// Fetches the computed result of the projection and decodes it to the given type.
    ///
    /// - Parameters:
    ///   - _: The `Decodable` type to decode the result into.
    ///   - configure: Closure to customise result options such as the partition key.
    /// - Returns: The decoded result, or `nil` if the server returns an empty response.
    /// - Throws: `KurrentError.decodingError` if the response cannot be decoded; `KurrentError` for transport failures.
    public func result<DecodeType: Decodable>(of _: DecodeType.Type, configure: @Sendable (inout Result.Options) -> Void = { _ in }) async throws(KurrentError) -> DecodeType? {
        var options = Result.Options()
        configure(&options)
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

    /// Fetches the current state of the projection and decodes it to the given type.
    ///
    /// - Parameters:
    ///   - _: The `Decodable` type to decode the state into.
    ///   - configure: Closure to customise state options such as the partition key.
    /// - Returns: The decoded state, or `nil` if the server returns an empty response.
    /// - Throws: `KurrentError.decodingError` if the response cannot be decoded; `KurrentError` for transport failures.
    public func state<DecodeType: Decodable>(of _: DecodeType.Type, configure: @Sendable (inout State.Options) -> Void = { _ in }) async throws(KurrentError) -> DecodeType? {
        var options = State.Options()
        configure(&options)
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
