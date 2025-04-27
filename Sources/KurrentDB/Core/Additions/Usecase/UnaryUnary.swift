//
//  UnaryUnary.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//
import NIO
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension UnaryUnary where UnderlyingResponse == EventStore_Client_Empty {
    package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws {
        _ = try await send(connection: connection, request: request(metadata: metadata), callOptions: callOptions)
    }
}

extension UnaryUnary where Transport == HTTP2ClientTransport.Posix {
    package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws -> Response {
        try await send(connection: connection, request: request(metadata: metadata), callOptions: callOptions)
    }
    
    package func perform(endpoint: Endpoint, settings: ClientSettings, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let node = try Node(endpoint: endpoint, settings: settings)
        return try await perform(node: node, callOptions: callOptions)
    }
    
    package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let node = try await selector.select()
        return try await perform(node: node, callOptions: callOptions)
    }

    package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let client = try await node.makeClient()
        return try await withRethrowingError(usage: #function) {
            return try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    try await client.runConnections()
                }
                let metadata = Metadata(from: node.settings)
                let response = try await send(connection: client, metadata: metadata, callOptions: callOptions)
                client.beginGracefulShutdown()
                return response
            }
        }
    }
    
}
