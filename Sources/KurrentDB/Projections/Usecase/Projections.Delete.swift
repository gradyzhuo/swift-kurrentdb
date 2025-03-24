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

        package func send(client: ServiceClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            do{
                return try await client.delete(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            }catch let error as RPCError {
                if error.message.contains("NotFound"){
                    throw KurrentError.resourceNotFound(reason: "Projection \(name) not found.")
                }
                
                throw KurrentError.grpc(code: try error.unpackGoogleRPCStatus(), reason: "Unknown error occurred, \(error.message)")
            }catch {
                throw KurrentError.serverError("Unknown error occurred: \(error)")
            }
        }
    }
}

extension Projections.Delete {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var deleteCheckpointStream: Bool
        public private(set) var deleteEmittedStreams: Bool
        public private(set) var deleteStateStream: Bool

        public init() {
            self.deleteCheckpointStream = false
            self.deleteEmittedStreams = false
            self.deleteStateStream = false
        }

        package func build() -> UnderlyingMessage {
            .with { message in
                message.deleteStateStream = deleteStateStream
                message.deleteEmittedStreams = deleteEmittedStreams
                message.deleteCheckpointStream = deleteCheckpointStream
            }
        }

        @discardableResult
        public func delete(emittedStreams enabled: Bool) -> Self {
            withCopy { options in
                options.deleteEmittedStreams = enabled
            }
        }

        @discardableResult
        public func delete(stateStream enabled: Bool) -> Self {
            withCopy { options in
                options.deleteStateStream = enabled
            }
        }

        @discardableResult
        public func delete(checkpointStream enabled: Bool) -> Self {
            withCopy { options in
                options.deleteCheckpointStream = enabled
            }
        }
    }
}
