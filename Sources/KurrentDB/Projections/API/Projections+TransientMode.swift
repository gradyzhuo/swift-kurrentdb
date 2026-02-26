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

//MARK: - Specified Transient Projection
extension Projections where Target == SpecifiedTransientProjectionTarget {
    /// Creates a transient projection with the specified query.
    ///
    /// - Parameters:
    ///   - query: The query string defining the projection.
    /// - Throws: An error if the creation process fails.
    public func create(query: String) async throws(KurrentError) {
        let usecase = TransientCreate(name: target.name, query: query)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

//MARK: - Unspecified Transient Projection
extension Projections where Target == UnspecifiedTransientProjectionTarget {
    
    /// Lists all transient projections and returns their detailed statistics.
    ///
    /// This asynchronous method queries the server for all projections in transient mode
    /// and aggregates their detailed information into a single array.
    ///
    /// - Returns: An array of `Statistics.Detail` representing each transient projection's details.
    /// - Throws: `KurrentError` if the request fails or if an internal client error occurs while
    ///           aggregating the response stream.
    /// - Note: Internally, this performs a list-all operation scoped to the transient projection mode
    ///         and reduces the streamed responses into a single result set.
    public func list() async throws(KurrentError) -> [Projection.Detail] {
        let usecase = Statistics(options: .listAll(mode: .transient))
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
