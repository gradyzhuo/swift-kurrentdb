//
//  PersistentSubscriptions.AllStream.Delete.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/7.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream{
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let groupName: String

        internal init(group groupName: String) {
            self.groupName = groupName
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .with { 
                    $0.all = .init()
                    $0.groupName = groupName
                }
                
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
