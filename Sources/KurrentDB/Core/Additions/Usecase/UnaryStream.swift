//
//  UnaryStream.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension UnaryStream where Transport == HTTP2ClientTransport.Posix, Responses == AsyncThrowingStream<Response, Error> {
    package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Responses where Responses.Element == Response {
        let client = try node.makeClient()
        Task {
            try await client.runConnections()
        }

        return try await withRethrowingError(usage: "\(Self.self)\(#function)") {
            let metadata = Metadata(from: node.settings)
            let request = try request(metadata: metadata)
            return try await send(connection: client, request: request, callOptions: callOptions){
                if let error = $0 {
                    logger.error("The error is thrown in the response of UnaryStream: \(error)")
                }
                client.beginGracefulShutdown()
            }
        }
    }

    package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Responses where Responses.Element == Response {
        let node = try await selector.select()
        return try await perform(node: node, callOptions: callOptions)
    }
}

extension UnaryStream where Transport == HTTP2ClientTransport.Posix {
    package func perform(endpoint: Endpoint, settings: ClientSettings, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        let client = try settings.makeClient(endpoint: endpoint)
        let metadata = Metadata(from: settings)
        return try await perform(client: client, metadata: metadata, callOptions: callOptions)
    }

    package func perform(selector: NodeSelector, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        let node = try await selector.select()
        return try await perform(node: node, callOptions: callOptions)
    }

    package func perform(node: Node, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        let client = try node.makeClient()
        let metadata = Metadata(from: node.settings)
        return try await perform(client: client, metadata: metadata, callOptions: callOptions)
    }

    package func perform(client: GRPCClient<HTTP2ClientTransport.Posix>, metadata: Metadata, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        Task {
            try await client.runConnections()
        }

        return try await withRethrowingError(usage: "\(Self.self)\(#function)") {
            let request = try request(metadata: metadata)
            return try await send(connection: client, request: request, callOptions: callOptions){
                if let error = $0 {
                    logger.error("The error is thrown in the response of UnaryStream: \(error)")
                }
                client.beginGracefulShutdown()
            }
        }
    }
}
