//
//  UnaryStream.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

extension UnaryStream where Transport == HTTP2ClientTransport.Posix, Responses == AsyncThrowingStream<Response, Error>{

    package func perform(settings: ClientSettings, callOptions: CallOptions) async throws -> Responses where Responses.Element == Response{
        let client = try GRPCClient(settings: settings)
        Task{
            try await client.runConnections()
        }
        
        let metadata = Metadata(from: settings)
        let request = try request(metadata: metadata)
        
        let underlying = Client.UnderlyingClient(wrapping: client)
        return try await send(client: underlying, request: request, callOptions: callOptions)
    }
}


extension UnaryStream where Transport == HTTP2ClientTransport.Posix{

    package func perform(settings: ClientSettings, callOptions: CallOptions) async throws -> Responses{
        let client = try GRPCClient(settings: settings)
        Task{
            try await client.runConnections()
        }
        
        let metadata = Metadata(from: settings)
        let request = try request(metadata: metadata)
        
        let underlying = Client.UnderlyingClient(wrapping: client)
        return try await send(client: underlying, request: request, callOptions: callOptions)
    }
}
