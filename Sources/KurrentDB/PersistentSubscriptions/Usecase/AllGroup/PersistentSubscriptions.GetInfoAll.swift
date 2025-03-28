//
//  PersistentSubscriptions.GetInfo.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/10.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions where Target == PersistentSubscription.AllGroup{
    public struct GetInfoAllGroup: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.GetInfo.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.GetInfo.Output
        package typealias Response = PersistentSubscription.SubscriptionInfo

        public let group: String

        public init(group: String) {
            self.group = group
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .init()
                $0.options.all = .init()
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
