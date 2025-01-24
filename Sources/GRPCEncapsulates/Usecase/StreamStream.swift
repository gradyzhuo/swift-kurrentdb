//
//  StreamStream.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore

package protocol StreamStream: Usecase, StreamRequestBuildable, StreamResponseHandlable {
    func send(client: ServiceClient, metadata: Metadata, callOptions: CallOptions) async throws -> Responses
}
