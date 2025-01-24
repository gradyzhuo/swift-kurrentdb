//
//  PersistentSubscriptionsClient.GetInfo.swift
//
//
//  Created by Grady Zhuo on 2023/12/10.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct GetInfo: UnaryUnary {
        public typealias ServiceClient = Client
        public typealias UnderlyingRequest = UnderlyingService.Method.GetInfo.Input
        public typealias UnderlyingResponse = UnderlyingService.Method.GetInfo.Output
        public typealias Response = PersistentSubscription.SubscriptionInfo

        public let streamSelection: StreamSelector<StreamIdentifier>
        public let groupName: String
        
        public init(streamSelection: StreamSelector<StreamIdentifier>, groupName: String) {
            self.streamSelection = streamSelection
            self.groupName = groupName
        }

        package func requestMessage() throws -> UnderlyingRequest {
            return try .with {
                switch streamSelection {
                case let .specified(streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                case .all:
                    $0.options.all = .init()
                }
                $0.options.groupName = groupName
            }
        }
        
        public func send(client: Client, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> PersistentSubscription.SubscriptionInfo {
            return try await client.getInfo(request: request, options: callOptions){
                try .init(from: $0.message.subscriptionInfo)
            }
        }
    }

}
