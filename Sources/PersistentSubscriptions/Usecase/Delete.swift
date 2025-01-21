//
//  PersistentSubscriptionsClient.Delete.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct Delete: UnaryUnary {
    public typealias Client = PersistentSubscriptions.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Delete.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Delete.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    let streamSelection: Selector<Stream.Identifier>
    let groupName: String

    internal init(streamSelection: Selector<Stream.Identifier>, groupName: String) {
        self.streamSelection = streamSelection
        self.groupName = groupName
    }
    
    public func requestMessage() throws -> UnderlyingRequest {
        return try .with {
            $0.options.groupName = groupName
            switch streamSelection {
            case .all:
                $0.options.all = .init()
            case let .specified(streamIdentifier):
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.delete(request: request, options: callOptions){
            try handle(response: $0)
        }
    }

}
