//
//  Projections.ContinuousCreate.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/22.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct ContinuousCreate: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        public let name: String
        public let query: String
        public let options: Options

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.continuous.name = name
                $0.options.query = query
            }
        }

        package func send(client: ServiceClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            do{
                return try await client.create(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            }catch let error as RPCError{
                if error.message.contains("Conflict"){
                    throw EventStoreError.resourceAlreadyExists
                }
                throw EventStoreError.grpc(code: .init(code: error.code, message: error.message, details: []), reason: error.message)
            }catch {
                throw EventStoreError.serverError("unexpected error: \(error)")
            }
        }
    }
}

// MARK: - The Options of Continuous Create.

extension Projections.ContinuousCreate {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var emitEnabled: Bool
        public private(set) var trackEmittedStreams: Bool

        public init(emitEnabled: Bool = true, trackEmittedStreams: Bool = true) {
            self.emitEnabled = emitEnabled
            self.trackEmittedStreams = trackEmittedStreams
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.continuous = .with {
                    $0.emitEnabled = emitEnabled
                    $0.trackEmittedStreams = trackEmittedStreams
                }
            }
        }

        @discardableResult
        public func emit(enabled: Bool) -> Self {
            withCopy { options in
                options.emitEnabled = enabled
            }
        }

        @discardableResult
        public func trackEmittedStreams(_ trackEmittedStreams: Bool) -> Self {
            withCopy { options in
                options.trackEmittedStreams = trackEmittedStreams
            }
        }
    }
}
