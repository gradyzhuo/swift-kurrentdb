//
//  StreamUnary.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension StreamUnary where Transport == HTTP2ClientTransport.Posix {
    package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws -> Response {
        try await send(connection: connection, request: request(metadata: metadata), callOptions: callOptions)
    }

    package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let node = try await selector.select()
        return try await perform(node: node, callOptions: callOptions)
    }

    package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let client = try node.makeClient()
        let metadata = Metadata(from: node.settings)
        return try await perform(client: client, metadata: metadata, callOptions: callOptions)
    }

    package func perform(endpoint: Endpoint, settings: ClientSettings, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let client = try settings.makeClient(endpoint: endpoint)
        let metadata = Metadata(from: settings)
        return try await perform(client: client, metadata: metadata, callOptions: callOptions)
    }

    package func perform(client: GRPCClient<HTTP2ClientTransport.Posix>, metadata: Metadata, callOptions: CallOptions) async throws(KurrentError) -> Response {
        try await withRethrowingError(usage: "\(Self.self)\(#function)") {
            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    logger.info("[\(Self.self)] connection opened by \(#function)")
                    try await client.runConnections()
                }
                let response = try await send(connection: client, metadata: metadata, callOptions: callOptions)
                logger.info("[\(Self.self)] connection closed by \(#function)")
                client.beginGracefulShutdown()
                return response
            }
        }
    }
}
