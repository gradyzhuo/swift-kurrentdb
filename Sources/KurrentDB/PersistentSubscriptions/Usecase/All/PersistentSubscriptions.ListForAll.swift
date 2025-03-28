//
//  PersistentSubscriptions.List.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions where Target == PersistentSubscription.All{
    public struct ListForAll: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.List.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.List.Output
        package typealias Response = [PersistentSubscription.SubscriptionInfo]

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options.listAllSubscriptions = .init()
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.list(request: request, options: callOptions) {
                try $0.message.subscriptions.map { .init(from: $0) }
            }
        }
    }
}
