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

extension Projections where Target == OneTimeProjectionTarget {
    /// Creates a continuous projection with the specified query and options.
    ///
    /// - Parameters:
    ///   - query: The query string defining the projection.
    ///   - options: The options for creating the projection. Defaults to an empty configuration.
    /// - Throws: An error if the creation process fails.
    public func create(query: String) async throws(KurrentError) {
        do {
            let usecase = OneTimeCreate(query: query)
            _ = try await usecase.perform(selector: selector, callOptions: callOptions)
        } catch {
            print(error)
        }
    }
    
}

extension Projections where Target == OneTimeProjectionTarget {

    /// Retrieves a list of one-time projection statistics.
    ///
    /// This asynchronous method queries the server for all one-time projections and
    /// returns their detailed statistics. Internally, it:
    /// - Constructs a `Statistics` use case configured to list all projections in `.oneTime` mode.
    /// - Performs the request using the current `selector` and `callOptions`.
    /// - Streams and reduces the server responses into an array of `Statistics.Detail`.
    ///
    /// - Returns: An array of `Statistics.Detail` describing each one-time projection.
    ///
    /// - Throws: `KurrentError`
    ///   - `.internalClientError` if an error occurs while reducing or processing the streamed responses,
    ///     with a reason describing the underlying cause.
    ///   - Any other `KurrentError` propagated from the use case execution.
    ///
    /// - Note: This method is available when `Projections.Target` is `OneTimeProjectionTarget`.
    ///
    /// - SeeAlso: `Statistics`, `Statistics.Detail`, `OneTimeProjectionTarget`
    public func list() async throws(KurrentError) -> [Projection.Detail] {
        let usecase = Statistics(options: .listAll(mode: .oneTime))
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
