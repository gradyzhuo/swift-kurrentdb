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

        public let stream: StreamSelector<StreamIdentifier>
        public let groupName: String

        public init(stream: StreamSelector<StreamIdentifier>, groupName: String) {
            self.stream = stream
            self.groupName = groupName
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                switch stream {
                case let .specified(streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                case .all:
                    $0.options.all = .init()
                }
                $0.options.groupName = groupName
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> PersistentSubscription.SubscriptionInfo {
            try await client.getInfo(request: request, options: callOptions) {
                try .init(from: $0.message.subscriptionInfo)
            }
        }
    }
}
