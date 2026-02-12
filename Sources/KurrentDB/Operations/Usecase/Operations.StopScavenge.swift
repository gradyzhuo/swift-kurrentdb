//
//  Operations.StopScavenge.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import GRPCCore
import GRPCEncapsulates

extension Operations {
    public struct StopScavenge: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.StopScavenge.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.StopScavenge.Output
        public typealias Response = ScavengeResponse

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.StopScavenge.descriptor
            }
        }

        package static var name: String{
            get{
                "Operations.\(Self.self)"
            }
        }
        
        let scavengeId: String

        public init(scavengeId: String) {
            self.scavengeId = scavengeId
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = .with {
                    $0.scavengeID = scavengeId
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.stopScavenge(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
