//
//  PersistentSubscriptions.UpdateToStream.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/12.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct UpdateToStream: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        var streamIdentifier: StreamIdentifier
        var group: String
        var options: Options

        init(streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.update(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.UpdateToStream {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var settings: PersistentSubscription.Settings
        public private(set) var revisionCursor: Cursor<StreamRevision>

        public init(settings: PersistentSubscription.Settings = .init(), revisionCursor: Cursor<StreamRevision> = .end) {
            self.settings = settings
            self.revisionCursor = revisionCursor
        }

        @discardableResult
        public func startFrom(cursor: Cursor<StreamRevision>) -> Self {
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
                    $0.stream.revision = revision.value
                }
            }
        }
    }
}
