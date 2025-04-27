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

        public let streamIdentifier: StreamIdentifier?
        public let group: String

        init(stream streamIdentifier: StreamIdentifier, group: String) {
            self.streamIdentifier = streamIdentifier
            self.group = group
        }
        
        init(group: String) {
            self.streamIdentifier = nil
            self.group = group
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = .init()
                $0.options.groupName = group
                if let streamIdentifier {
                    $0.options.streamIdentifier = try streamIdentifier.build()
                }else{
                    $0.options.all = .init()
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
