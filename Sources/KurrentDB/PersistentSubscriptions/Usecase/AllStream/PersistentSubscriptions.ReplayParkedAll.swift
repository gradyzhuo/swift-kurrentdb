//
//  PersistentSubscriptions.ReplayParked.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct ReplayParkedAll: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.ReplayParked.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.ReplayParked.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let group: String
        let options: ReplayParkedOptions
        
        public init(group: String, options: ReplayParkedOptions) {
            self.group = group
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.all = .init()
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.replayParked(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}


