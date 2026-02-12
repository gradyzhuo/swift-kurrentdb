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

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.Update.descriptor
            }
        }

        package static var name: String{
            get{
                "Projections.\(Self.self)"
            }
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

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            do {
                return try await client.update(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            } catch let error as RPCError {
                if error.message.contains("NotFound") {
                    throw KurrentError.resourceNotFound(reason: "Projection \(name) not found.")
                }
                throw try KurrentError.grpc(code: error.unpackGoogleRPCStatus(), reason: "Unknown error occurred.")
            } catch {
                throw KurrentError.serverError("Unknown error occurred, cause: \(error)")
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

        @discardableResult
        public func noEmit() -> Self {
            withCopy { options in
                options.emitOption = .noEmit
            }
        }

        @discardableResult
        public func emit(enabled: Bool) -> Self {
            withCopy { options in
                options.emitOption = .enable(enabled)
            }
        }
    }
}
