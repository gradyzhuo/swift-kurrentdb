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
    /// Returns statistics for all projections regardless of mode.
    ///
    /// - Returns: An array of ``Projection/Detail`` describing every projection on the server.
    /// - Throws: `KurrentError` if the request fails or the response stream cannot be read.
    public func list() async throws(KurrentError) -> [Projection.Detail] {
        let usecase = Statistics(options: .listAll(mode: .any))
        let response = try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
        do {
            return try await response.reduce(into: .init()) { partialResult, response in
                partialResult.append(response.detail)
            }
        } catch {
            throw .internalClientError(reason: "The error happened while get the list of projections, cause: \(error)")
        }
    }

    /// Restarts the entire projection subsystem on the server.
    ///
    /// - Throws: `KurrentError` if the server rejects the request or a transport failure occurs.
    public func restartSubsystem() async throws(KurrentError) {
        let usecase = RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: callOptions, credentials: overrideCredentials)
    }
}
