//
//  UnaryUnary+Additions.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore

package protocol UnaryUnary: Usecase, UnaryRequestBuildable, UnaryResponseHandlable {
    func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response
}
