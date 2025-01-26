//
//  Operations.StopScavenge.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct StopScavenge: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.StopScavenge.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.StopScavenge.Output
        public typealias Response = ScavengeResponse

        let scavengeId: String
        
        public init(scavengeId: String) {
            self.scavengeId = scavengeId
        }

        
        package func requestMessage() throws -> UnderlyingRequest {
            return .with {
                $0.options = .with {
                    $0.scavengeID = scavengeId
                }
            }
        }
        
        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            return try await client.stopScavenge(request: request, options: callOptions){
                try handle(response: $0)
            }
        }
    }

}
