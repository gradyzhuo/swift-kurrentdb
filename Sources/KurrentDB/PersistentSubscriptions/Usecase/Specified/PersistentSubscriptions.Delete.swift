//
//  PersistentSubscriptions.Delete.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/7.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions where Target == PersistentSubscription.Specified{
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let streamIdentifier: StreamIdentifier
        let groupName: String

        internal init(stream streamIdentifier: StreamIdentifier, group groupName: String) {
            self.streamIdentifier = streamIdentifier
            self.groupName = groupName
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options.groupName = groupName
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
