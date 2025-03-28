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
    package func perform(settings: ClientSettings, callOptions: CallOptions) async throws(KurrentError) -> Responses where Responses.Element == Response {
        let client = try GRPCClient(settings: settings)
        Task {
            try await client.runConnections()
        }

        let metadata = Metadata(from: settings)
        do{
            let request = try request(metadata: metadata)

            let underlying = ServiceClient(wrapping: client)
            return try await send(client: underlying, request: request, callOptions: callOptions)
        }catch {
            throw .internalClientError(reason: "\(Self.self) perform failed: \(error)", cause: error)
        }
        
    }
}

extension UnaryStream where Transport == HTTP2ClientTransport.Posix {
    package func perform(settings: ClientSettings, callOptions: CallOptions) async throws(KurrentError) -> Responses {
        let client = try GRPCClient(settings: settings)
        Task {
            try await client.runConnections()
        }
        
        return try await withRethrowingError(usage: #function) {
            let metadata = Metadata(from: settings)
            let request = try request(metadata: metadata)

            let underlying = ServiceClient(wrapping: client)
            return try await send(client: underlying, request: request, callOptions: callOptions)
        }
        
    }
}
