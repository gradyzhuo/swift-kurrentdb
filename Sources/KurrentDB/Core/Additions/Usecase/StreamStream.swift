//
//  StreamStream.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension StreamStream where Transport == HTTP2ClientTransport.Posix {
    package func perform(endpoint: Endpoint, settings: ClientSettings, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        let node = try Node(endpoint: endpoint, settings: settings)
        return try await perform(node: node, callOptions: callOptions)
    }
    
    package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        let client = try await node.makeClient()
        Task {
            try await client.runConnections()
        }

        let metadata = Metadata(from: node.settings)        
        return try await withRethrowingError(usage: #function) {
            return try await send(connection: client, metadata: metadata, callOptions: callOptions)
        }
    }
    
    package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        let node = try await selector.select()
        return try await perform(node: node, callOptions: callOptions)
    }
        
}
