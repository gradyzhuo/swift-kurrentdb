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

extension Projections where Target == ContinuousTarget {
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
