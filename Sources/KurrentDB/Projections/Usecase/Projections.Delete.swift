//
//  Projections.Delete.swift
//  KurrentProjections
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Projections {
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Delete.descriptor
        }

        package static var name: String {
            "Projections.\(Self.self)"
        }

        public let name: String
        public let options: Options

        init(name: String, options: Options) {
            self.name = name
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.name = name
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws(KurrentError) -> Response {
            let client = ServiceClient(wrapping: connection)
            do {
                return try await client.delete(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            } catch let error as RPCError {
                if error.message.contains("NotFound") {
                    throw .resourceNotFound(reason: "Projection \(name) not found.")
                }
                let code = try? error.unpackGoogleRPCStatus()
                throw .grpc(code: code, reason: "Unknown error occurred, \(error.message)")
            } catch {
                throw .serverError("Unknown error occurred, cause: \(error)")
            }
        }
    }
}

extension Projections.Delete {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        private var _deleteCheckpointStream: Bool
        private var _deleteEmittedStreams: Bool
        private var _deleteStateStream: Bool

        public init() {
            _deleteCheckpointStream = false
            _deleteEmittedStreams = false
            _deleteStateStream = false
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.deleteStateStream = _deleteStateStream
                $0.deleteEmittedStreams = _deleteEmittedStreams
                $0.deleteCheckpointStream = _deleteCheckpointStream
            }
        }

        @discardableResult
        public func deleteEmittedStreams() -> Self {
            withCopy { options in
                options._deleteEmittedStreams = true
            }
        }

        @discardableResult
        public func deleteStateStream() -> Self {
            withCopy { options in
                options._deleteStateStream = true
            }
        }

        @discardableResult
        public func deleteCheckpointStream() -> Self {
            withCopy { options in
                options._deleteCheckpointStream = true
            }
        }
    }
}
