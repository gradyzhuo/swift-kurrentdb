//
//  PersistentSubscriptionsClient.Delete.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let streamSelection: StreamSelector<StreamIdentifier>
        let groupName: String

        public init(streamSelection: StreamSelector<StreamIdentifier>, groupName: String) {
            self.streamSelection = streamSelection
            self.groupName = groupName
        }
        
        package func requestMessage() throws -> UnderlyingRequest {
            return try .with {
                $0.options.groupName = groupName
                switch streamSelection {
                case .all:
                    $0.options.all = .init()
                case let .specified(streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                }
            }
        }
        
        package func send(client: Client, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.delete(request: request, options: callOptions){
                try handle(response: $0)
            }
        }

    }
}
