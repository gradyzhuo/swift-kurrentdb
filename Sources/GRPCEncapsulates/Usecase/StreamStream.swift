//
//  StreamStream.swift
//  GRPCEncapsulates
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore

package protocol StreamStream: Usecase, StreamRequestBuildable, StreamResponseHandlable {
    func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws -> Responses
}
