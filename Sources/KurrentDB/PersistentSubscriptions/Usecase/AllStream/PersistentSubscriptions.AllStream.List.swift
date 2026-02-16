//
//  PersistentSubscriptions.AllStream.List.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream {
    public struct List: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.List.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.List.Output
        package typealias Response = [PersistentSubscription.SubscriptionInfo]

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.List.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        init() {}

        /// Constructs a request message to list all persistent subscriptions across all streams.
        ///
        /// - Returns: An underlying request configured to retrieve all persistent subscriptions.
        /// - Throws: An error if the request message cannot be constructed.
        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .with {
                    $0.listForStream.all = .init()
                }
            }
        }

        /// Sends a request to list all persistent subscriptions across streams and returns their information.
        ///
        /// - Returns: An array of `PersistentSubscription.SubscriptionInfo` representing all persistent subscriptions.
        /// - Throws: An error if the request fails or the response cannot be processed.
        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.list(request: request, options: callOptions) {
                try $0.message.subscriptions.map { .init(from: $0) }
            }
        }
    }
}
