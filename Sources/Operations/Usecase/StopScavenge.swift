//
//  Operations.StopScavenge.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

public struct StopScavenge: UnaryUnary {
    public typealias Client = Operations.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.StopScavenge.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.StopScavenge.Output
    public typealias Response = ScavengeResponse

    let scavengeId: String
    
    public init(scavengeId: String) {
        self.scavengeId = scavengeId
    }

    
    package func requestMessage() throws -> UnderlyingService.Method.StopScavenge.Input {
        return .with {
            $0.options = .with {
                $0.scavengeID = scavengeId
            }
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.stopScavenge(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}
