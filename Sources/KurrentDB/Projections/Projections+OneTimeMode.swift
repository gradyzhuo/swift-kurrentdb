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

extension Projections where Target == OneTimeTarget {
    /// Creates a continuous projection with the specified query and options.
    ///
    /// - Parameters:
    ///   - query: The query string defining the projection.
    ///   - options: The options for creating the projection. Defaults to an empty configuration.
    /// - Throws: An error if the creation process fails.
    public func create(query: String) async throws(KurrentError) {
        do{
            let usecase = OneTimeCreate(query: query)
            _ = try await usecase.perform(selector: selector, callOptions: callOptions)
        }catch{
            print(error)
        }
        
    }
}
