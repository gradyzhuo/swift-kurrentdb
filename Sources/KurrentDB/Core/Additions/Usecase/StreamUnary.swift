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
        guard node.serverInfo.isSupported(method: methodDescriptor) else {
            throw .unsupportedFeature(methodDescriptor)
        }
        
        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            try await withGRPCClient(transport: .http2NIOPosix(
                target: node.endpoint.target,
                transportSecurity: node.settings.transportSecurity
            )) { client in
                logger.debug("[\(Self.name)] Opening connection...")
                let metadata = Metadata(from: node.settings)
                return try await perform(client: client, settings: node.settings, callOptions: callOptions)
            }
        }
    }

    package func perform(client: GRPCClient<HTTP2ClientTransport.Posix>, settings: ClientSettings, callOptions: CallOptions) async throws(KurrentError) -> Response {
        let metadata = Metadata(from: settings)
        return try await withRethrowingError(usage: "\(Self.self)\(#function)") {
            let response = try await send(connection: client, metadata: metadata, callOptions: callOptions)
            logger.debug("[\(Self.name)] Closing connection...")
            client.beginGracefulShutdown()
            return response
        }
    }
}
