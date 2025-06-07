//
//  PersistentSubscriptions.GetInfo.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/10.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    public struct GetInfo: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.GetInfo.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.GetInfo.Output
        package typealias Response = PersistentSubscription.SubscriptionInfo

        public let streamIdentifier: StreamIdentifier
        public let group: String

        init(stream streamIdentifier: StreamIdentifier, group: String) {
            self.streamIdentifier = streamIdentifier
            self.group = group
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = try .with { 
                    $0.streamIdentifier = try streamIdentifier.build()
                    $0.groupName = group
                }
                
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> PersistentSubscription.SubscriptionInfo {
            let client = ServiceClient(wrapping: connection)
            return try await client.getInfo(request: request, options: callOptions) {
                try .init(from: $0.message.subscriptionInfo)
            }
        }
    }
}
