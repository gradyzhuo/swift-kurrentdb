//
//  PersistentSubscriptions.AllStream.Delete.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/7.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream {
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.Delete.descriptor
            }
        }

        package static var name: String{
            get{
                "PersistentSubscriptions.\(Self.self)"
            }
        }
        
        let groupName: String

        init(group groupName: String) {
            self.groupName = groupName
        }

        /// Constructs the gRPC request message to delete a persistent subscription group on all streams.
        ///
        /// - Returns: The underlying request message configured for deleting the specified group.
        /// - Throws: An error if the request message cannot be constructed.
        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .with {
                    $0.all = .init()
                    $0.groupName = groupName
                }
            }
        }

        /// Sends a request to delete a persistent subscription group on all streams.
        ///
        /// - Returns: A `DiscardedResponse` indicating the result of the delete operation.
        /// - Throws: An error if the request fails or the response cannot be handled.
        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
