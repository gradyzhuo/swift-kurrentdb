//
//  PersistentSubscriptions.GetInfo.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/10.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct GetInfo: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.GetInfo.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.GetInfo.Output
        package typealias Response = PersistentSubscription.SubscriptionInfo

        public let streamIdentifier: StreamIdentifier
        public let group: String

        public init(stream streamIdentifier: StreamIdentifier, group: String) {
            self.streamIdentifier = streamIdentifier
            self.group = group
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = .init()
                $0.options.streamIdentifier = try streamIdentifier.build()
                $0.options.groupName = group
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> PersistentSubscription.SubscriptionInfo {
            try await client.getInfo(request: request, options: callOptions) {
                try .init(from: $0.message.subscriptionInfo)
            }
        }
    }
}
