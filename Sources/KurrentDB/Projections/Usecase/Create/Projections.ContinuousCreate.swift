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

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Create.descriptor
        }

        package static var name: String {
            "Projections.\(Self.self)"
        }

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

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws(KurrentError) -> Response {
            try await withRethrowingError(usage: Self.name) {
                let client = ServiceClient(wrapping: connection)
                return try await client.create(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            }
        }
    }
}

// MARK: - The Options of Continuous Create.

extension Projections.ContinuousCreate {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var emitEnabled: Bool
        public var trackEmittedStreams: Bool

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
    }
}
