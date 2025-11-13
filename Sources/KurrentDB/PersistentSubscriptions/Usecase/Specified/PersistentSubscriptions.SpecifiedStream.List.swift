//
//  PersistentSubscriptions.SpecifiedStream.List.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    public struct List: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.List.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.List.Output
        package typealias Response = [PersistentSubscription.SubscriptionInfo]
        
        package static var name: String{
            get{
                "PersistentSubscriptions.\(Self.self)"
            }
        }
        
        public let streamIdentifier: StreamIdentifier?

        init(stream streamIdentifier: StreamIdentifier) {
            self.streamIdentifier = streamIdentifier
        }

        init() {
            streamIdentifier = nil
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                if let streamIdentifier {
                    $0.options.listForStream.stream = try streamIdentifier.build()
                } else {
                    $0.options.listForStream.all = .init()
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.list(request: request, options: callOptions) {
                try $0.message.subscriptions.map { .init(from: $0) }
            }
        }
    }
}
