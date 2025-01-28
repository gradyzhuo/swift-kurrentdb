//
//  UnaryStream.swift
//  GRPCEncapsulates
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore

package protocol UnaryStream: Usecase, UnaryRequestBuildable, StreamResponseHandlable {
    func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses
}
