//
//  PersistentSubscriptions.List.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions where Target == PersistentSubscription.AllStream{
    public struct ListForStream: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.List.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.List.Output
        package typealias Response = [PersistentSubscription.SubscriptionInfo]

        public let streamIdentifier: StreamIdentifier

        internal init(stream streamIdentifier: StreamIdentifier) {
            self.streamIdentifier = streamIdentifier
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options.listForStream.stream = try streamIdentifier.build()
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.list(request: request, options: callOptions) {
                try $0.message.subscriptions.map { .init(from: $0) }
            }
        }
    }
}
