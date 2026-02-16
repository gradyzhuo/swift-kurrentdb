//
//  PersistentSubscriptions.AllStream.GetInfo.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/10.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream {
    public struct GetInfo: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.GetInfo.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.GetInfo.Output
        package typealias Response = PersistentSubscription.SubscriptionInfo

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.GetInfo.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        public let group: String

        init(group: String) {
            self.group = group
        }

        /// Constructs a request message to retrieve persistent subscription information for the specified group on the `$all` stream.
        ///
        /// - Throws: An error if the request message cannot be constructed.
        /// - Returns: The underlying gRPC request message targeting the `$all` stream and the specified group.
        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .with {
                    $0.all = .init()
                    $0.groupName = group
                }
            }
        }

        /// Sends a gRPC request to retrieve subscription information for the specified group on the `$all` persistent subscription.
        ///
        /// - Returns: The subscription information for the requested group.
        ///
        /// - Throws: An error if the gRPC call fails or the response cannot be parsed.
        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> PersistentSubscription.SubscriptionInfo {
            let client = ServiceClient(wrapping: connection)
            return try await client.getInfo(request: request, options: callOptions) {
                try .init(from: $0.message.subscriptionInfo)
            }
        }
    }
}
