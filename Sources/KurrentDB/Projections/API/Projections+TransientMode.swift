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
    /// Creates a transient projection on the server with the given query.
    ///
    /// - Parameter query: JavaScript query string that defines the projection logic.
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func create(query: String) async throws(KurrentError) {
        let usecase = TransientCreate(name: target.name, query: query)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

//MARK: - Unspecified Transient Projection
extension Projections where Target == UnspecifiedTransientProjectionTarget {

    /// Returns statistics for all transient projections on the server.
    ///
    /// - Returns: An array of ``Projection/Detail`` for each transient projection.
    /// - Throws: `KurrentError` if the request fails or the response stream cannot be read.
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
