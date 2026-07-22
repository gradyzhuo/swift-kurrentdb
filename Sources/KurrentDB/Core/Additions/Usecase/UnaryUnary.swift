//
//  UnaryUnary.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import NIO

extension UnaryUnary where UnderlyingResponse == EventStore_Client_Empty {
    package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws {
        _ = try await send(connection: connection, request: request(metadata: metadata), callOptions: callOptions)
    }
}

extension UnaryUnary where Transport == HTTP2ClientTransport.Posix {
    package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws -> Response {
        try await send(connection: connection, request: request(metadata: metadata), callOptions: callOptions)
    }

    package func perform(selector: NodeSelector, callOptions: CallOptions, credentials: Authentication? = nil) async throws(KurrentError) -> Response {
        try await withRetry(
            policy: selector.retryPolicy,
            selectNode: { try await selector.select() },
            invalidate: { await selector.invalidate() }
        ) { node in
            try await perform(node: node, callOptions: callOptions, credentials: credentials)
        }
    }

    package func perform(node: Node, callOptions: CallOptions, credentials: Authentication? = nil) async throws(KurrentError) -> Response {
        guard node.serverInfo.isSupported(method: methodDescriptor) else {
            throw .unsupportedFeature(methodDescriptor)
        }
        
        let client = try GRPCClient<HTTP2ClientTransport.Posix>(from: node)
        Task {
            logger.debug("[\(Self.name)] Opening connection...")
            try await client.runConnections()
        }
        
        defer{
            logger.debug("[\(Self.name)] Closing connection...")
            client.beginGracefulShutdown()
        }
        
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            logger.debug("[\(Self.name)] Opening connection...")
            let metadata = try Metadata(from: node.settings, overriding: credentials)
            return try await send(connection: client, metadata: metadata, callOptions: callOptions)
        }
    }
}
