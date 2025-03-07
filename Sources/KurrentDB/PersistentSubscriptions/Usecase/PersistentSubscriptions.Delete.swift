//
//  PersistentSubscriptions.Delete.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/7.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let stream: StreamSelector<StreamIdentifier>
        let group: String

        public init(stream: StreamSelector<StreamIdentifier>, group: String) {
            self.stream = stream
            self.group = group
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options.groupName = group
                switch stream {
                case .all:
                    $0.options.all = .init()
                case let .specified(streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                }
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
