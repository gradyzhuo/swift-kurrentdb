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
    /// Creates a one-time projection on the server with the given query.
    ///
    /// - Parameter query: JavaScript query string that defines the projection logic.
    ///
    /// Errors encountered during creation are logged to stdout but not rethrown.
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

    /// Returns statistics for all one-time projections on the server.
    ///
    /// - Returns: An array of ``Projection/Detail`` for each one-time projection.
    /// - Throws: `KurrentError` if the request fails or the response stream cannot be read.
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
