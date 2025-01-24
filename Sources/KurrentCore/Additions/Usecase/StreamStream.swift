//
//  StreamStream.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/20.
//

import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

extension StreamStream where Transport == HTTP2ClientTransport.Posix{
    
    package func perform(settings: ClientSettings, callOptions: CallOptions) async throws -> Responses{
        let client = try GRPCClient(settings: settings)
        Task{
            try await client.runConnections()
        }
        
        let metadata = Metadata(from: settings)
        let serviceClient = ServiceClient(wrapping: client)
        return try await send(client: serviceClient, metadata: metadata, callOptions: callOptions)
    }
}
