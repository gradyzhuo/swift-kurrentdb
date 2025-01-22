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
        let underlying = Client.UnderlyingClient(wrapping: client)
        return try await send(client: underlying, metadata: metadata, callOptions: callOptions)
    }
    
//    package func send(client: Client.UnderlyingClient, metadata: Metadata, callOptions: CallOptions) async throws -> StreamingClientResponse<UnderlyingResponse>{
//        return try await send(client: client, request: request(metadata: metadata), callOptions: callOptions)
//    }
    
    //TODO: 要補回來
//    package func perform(settings: ClientSettings, callOptions: CallOptions) async throws -> AsyncThrowingStream<Self.Response, Error> where Responses.Element == Response{
//        let client = try GRPCClient(settings: settings)
//        let metadata = Metadata(from: settings)
//        
//        return try await withThrowingDiscardingTaskGroup { group in
//            group.addTask {
//                try await client.runConnections()
//            }
//            let underlying = Client.UnderlyingClient(wrapping: client)
//            let responses = try await perform(client: underlying, metadata: metadata, callOptions: callOptions)
//            
//            return .init { continuation in
//                Task.detached {
//                    var iterator = responses.makeAsyncIterator()
//                    
//                    while let response = try await iterator.next() {
//                        continuation.yield(response)
//                    }
//                    client.beginGracefulShutdown()
//                    continuation.finish()
//                }
//            }
//        }
//    }
}
