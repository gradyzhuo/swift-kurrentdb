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
    public struct TransientCreate: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.Create.descriptor
            }
        }

        package static var name: String{
            get{
                "Projections.\(Self.self)"
            }
        }
        
        public let name: String
        public let query: String

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .with{
                    $0.transient = .with{
                        $0.name = name
                    }
                    $0.query = query
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws(KurrentError) -> Response {
            let client = ServiceClient(wrapping: connection)
            do {
                return try await client.create(request: request, options: callOptions) {
                    try handle(response: $0)
                }
            } catch let error as RPCError {
                if error.message.contains("Conflict") {
                    throw KurrentError.resourceAlreadyExists
                }
                throw .grpcError(cause: error)
            } catch {
                throw .serverError("unexpected error, cause: \(error)")
            }
        }
    }
}
