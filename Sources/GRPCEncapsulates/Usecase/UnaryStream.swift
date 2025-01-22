//
//  UnaryStream.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore

package protocol UnaryStream: Usecase, UnaryRequestBuildable, StreamResponseHandlable {
    func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses
}
