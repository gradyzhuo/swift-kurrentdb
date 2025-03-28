//
//  PersistentSubscriptions.DeleteAll.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/27.
//
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions where Target == PersistentSubscription.AllStream{
    public struct DeleteAllStream: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let streamIdentifier: StreamIdentifier

        public init(stream streamIdentifier: StreamIdentifier) {
            self.streamIdentifier = streamIdentifier
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options.streamIdentifier = try streamIdentifier.build()
                $0.options.all = .init()
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
