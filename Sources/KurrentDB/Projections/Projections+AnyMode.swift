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

//MARK: - Any Mode Projection
extension Projections where Target == AnyProjectionsTarget {
    /// Lists all projection statistics across any mode.
    ///
    /// This asynchronous function performs a request to retrieve projection statistics
    /// without restricting to a specific mode (i.e., it uses `.any`). It leverages the
    /// `Statistics` use case with the `.listAll(mode: .any)` option and returns the
    /// collected `Statistics.Detail` entries extracted from the streamed response.
    ///
    /// Behavior:
    /// - Builds a `Statistics` use case configured to list all projections for any mode.
    /// - Executes the use case with the current `selector` and `callOptions`.
    /// - Iterates over the streamed responses and accumulates their `detail` payloads.
    /// - If an error occurs during reduction/collection, it wraps it in
    ///   `KurrentError.internalClientError` with additional context.
    ///
    /// - Returns: An array of `Statistics.Detail` representing the details of each projection.
    ///
    /// - Throws: `KurrentError` in the following situations:
    ///   - Any error produced by the `Statistics.perform(selector:callOptions:)` call,
    ///     such as transport or server-side failures.
    ///   - `KurrentError.internalClientError` if an error occurs while reducing the
    ///     streamed response into the result array.
    ///
    /// - Note: This method requires an environment with valid `selector` and `callOptions`
    ///   configured on the `Projections` instance, as well as a functioning GRPC transport.
    ///
    /// - SeeAlso: `Statistics`, `Statistics.Options.listAll(mode:)`, `Statistics.Detail`
    public func list() async throws(KurrentError) -> [Statistics.Detail] {
        let usecase = Statistics(options: .listAll(mode: .any))
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
