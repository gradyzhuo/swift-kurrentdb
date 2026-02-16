//
//  PersistentSubscriptions.SpecifiedStream.Delete.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/7.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Delete.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Delete.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        let streamIdentifier: StreamIdentifier
        let groupName: String

        init(streamIdentifier: StreamIdentifier, group groupName: String) {
            self.streamIdentifier = streamIdentifier
            self.groupName = groupName
        }

        /// Constructs the gRPC request message for deleting a persistent subscription on a specified stream.
        ///
        /// - Throws: An error if building the stream identifier fails.
        ///
        /// - Returns: The underlying gRPC request message configured with the stream identifier and group name.
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = try .with {
                    $0.streamIdentifier = try streamIdentifier.build()
                    $0.groupName = groupName
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}
