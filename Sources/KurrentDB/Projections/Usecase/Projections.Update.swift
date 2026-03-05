//
//  Projections.Update.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Update: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Update.descriptor
        }

        package static var name: String {
            "Projections.\(Self.self)"
        }

        public let name: String
        public let query: String?
        public let options: Options

        public init(name: String, query: String? = nil, options: Options) {
            self.name = name
            self.query = query
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.name = name
                if let query {
                    $0.options.query = query
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws(KurrentError) -> Response {
            try await withRethrowingError(usage: Self.name) {
                let client = ServiceClient(wrapping: connection)
                return try await client.update(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            }
        }
    }
}

extension Projections.Update {
    public enum EmitOption: Sendable {
        case noEmit
        case enable(Bool)
    }

    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var emitOption: EmitOption

        public init() {
            emitOption = .noEmit
        }

        package func build() -> UnderlyingMessage {
            .with {
                switch emitOption {
                case .noEmit:
                    $0.noEmitOptions = .init()
                case let .enable(enabled):
                    $0.emitEnabled = enabled
                }
            }
        }
    }
}
