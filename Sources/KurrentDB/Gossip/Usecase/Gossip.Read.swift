//
//  Gossip.Read.swift
//  KurrentGossip
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Gossip {
    public struct Read: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Read.Output
        public typealias Response = [MemberInfo]

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.read(request: request, options: callOptions) {
                try $0.message.members.map {
                    try .init(from: $0)
                }
            }
        }
    }
}

