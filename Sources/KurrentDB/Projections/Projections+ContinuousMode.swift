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

//MARK: - Specified Continuous Projection
extension Projections where Target == SpecifiedContinuousProjectionTarget {
    /// Creates a continuous projection with the specified query and options.
    ///
    /// - Parameters:
    ///   - query: The query string defining the projection.
    ///   - options: The options for creating the projection. Defaults to an empty configuration.
    /// - Throws: An error if the creation process fails.
    public func create(query: String, options: ContinuousCreate.Options = .init()) async throws(KurrentError) {
        let usecase = ContinuousCreate(name: target.name, query: query, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

//MARK: - Unspecified Continuous Projection
extension Projections where Target == UnspecifiedContinuousProjectionTarget {

    /// Retrieves a list of continuous projection statistics from the server.
    ///
    /// This method queries the projections service for all continuous projections and
    /// returns an array of detailed statistics for each one. It constructs a `Statistics`
    /// use case configured to list all projections in continuous mode, performs the request
    /// using the current selector and call options, and then reduces the streamed responses
    /// into a collection of `Statistics.Detail` values.
    ///
    /// - Returns: An array of `Statistics.Detail` objects, each describing a continuous projection.
    ///
    /// - Throws: `KurrentError` in the following cases:
    ///   - `.internalClientError` if an error occurs while aggregating the streamed responses.
    ///   - Any other `KurrentError` that may be thrown by the underlying RPC call initiated by `perform`.
    ///
    /// - Important: This call is asynchronous and may perform network I/O. It should be awaited
    ///   from an asynchronous context.
    ///
    /// - Note: The results are derived from a streamed response; if any element in the stream
    ///   fails to decode or process, the entire operation throws.
    public func list() async throws(KurrentError) -> [Projection.Detail] {
        let usecase = Statistics(options: .listAll(mode: .continuous))
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
