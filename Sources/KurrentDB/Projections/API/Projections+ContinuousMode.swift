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
    /// Creates a continuous projection on the server with the given query.
    ///
    /// ```swift
    /// let projections = client.projections(of: .continuous(name: "order-stats"))
    /// try await projections.create(query: """
    ///     fromAll()
    ///       .when({ $any: (s, e) => { s.count = (s.count || 0) + 1; } })
    /// """) {
    ///     $0.emitEnabled = true
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - query: JavaScript query string that defines the projection logic.
    ///   - configure: Closure to customise creation options such as emit and track-emitted-streams settings.
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func create(query: String, configure: @Sendable (inout ContinuousCreate.Options) -> Void = { _ in }) async throws(KurrentError) {
        var options = ContinuousCreate.Options()
        configure(&options)
        let usecase = ContinuousCreate(name: target.name, query: query, options: options)
        _ = try await usecase.perform(selector: selector, callOptions: callOptions)
    }
}

//MARK: - Unspecified Continuous Projection
extension Projections where Target == UnspecifiedContinuousProjectionTarget {

    /// Returns statistics for all continuous projections on the server.
    ///
    /// - Returns: An array of ``Projection/Detail`` for each continuous projection.
    /// - Throws: `KurrentError` if the request fails or the response stream cannot be read.
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
