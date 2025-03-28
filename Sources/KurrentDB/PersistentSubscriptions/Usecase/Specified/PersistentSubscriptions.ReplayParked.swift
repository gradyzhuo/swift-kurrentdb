//
//  PersistentSubscriptions.ReplayParked.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct ReplayParked: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.ReplayParked.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.ReplayParked.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let streamIdentifier: StreamIdentifier
        let group: String
        let options: ReplayParkedOptions
        
        internal init(stream streamIdentifier: StreamIdentifier, group: String, options: ReplayParkedOptions) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.replayParked(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
