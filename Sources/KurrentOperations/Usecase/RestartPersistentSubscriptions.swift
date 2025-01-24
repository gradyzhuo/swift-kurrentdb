//
//  Operations.RestartPersistentSubscriptions.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct RestartPersistentSubscriptions: UnaryUnary {
        public typealias ServiceClient = Client
        public typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.RestartPersistentSubscriptions.Input
        public typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.RestartPersistentSubscriptions.Output
        public typealias Response = DiscardedResponse<UnderlyingResponse>
        
        public init(){}
        
        public func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.restartPersistentSubscriptions(request: request, options: callOptions){
                try handle(response: $0)
            }
        }
    }

}
