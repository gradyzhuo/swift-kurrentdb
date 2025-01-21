//
//  PersistentSubscriptionsClient.UpdateToStream.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/12.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct UpdateToStream: UnaryUnary {
    public typealias Client = PersistentSubscriptions.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Update.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Update.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    var streamIdentifier: KurrentCore.Stream.Identifier
    var groupName: String
    var options: Options
    
    internal init(streamIdentifier: KurrentCore.Stream.Identifier, groupName: String, options: Options) {
        self.streamIdentifier = streamIdentifier
        self.groupName = groupName
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return try .with {
            $0.options = options.build()
            $0.options.groupName = groupName
            $0.options.stream.streamIdentifier = try streamIdentifier.build()
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.update(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

extension UpdateToStream {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var settings: PersistentSubscription.Settings
        public private(set) var revisionCursor: KurrentCore.Cursor<KurrentCore.Stream.Revision>

        public init(settings: PersistentSubscription.Settings = .init(), revisionCursor: KurrentCore.Cursor<KurrentCore.Stream.Revision> = .end) {
            self.settings = settings
            self.revisionCursor = revisionCursor
        }
        
        @discardableResult
        public func startFrom(cursor: KurrentCore.Cursor<KurrentCore.Stream.Revision>) -> Self {
            withCopy { options in
                options.revisionCursor = cursor
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)

                switch revisionCursor {
                case .start:
                    $0.stream.start = .init()
                case .end:
                    $0.stream.end = .init()
                case let .specified(revision):
                    $0.stream.revision = revision
                }
            }
        }
    }
}
