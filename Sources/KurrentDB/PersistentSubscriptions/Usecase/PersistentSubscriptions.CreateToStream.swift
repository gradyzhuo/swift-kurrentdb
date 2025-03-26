//
//  PersistentSubscriptionsClient.CreateToStream.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/12.
//
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct CreateToStream: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        var streamIdentifier: StreamIdentifier
        var cursor: RevisionCursor
        var group: String
        var options: Options

        public init(streamIdentifier: StreamIdentifier, group: String, cursor: RevisionCursor, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.cursor = cursor
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
                $0.options.groupName = group
                
                switch cursor {
                case .start:
                    $0.options.stream.start = .init()
                case .end:
                    $0.options.stream.end = .init()
                case let .revision(revision):
                    $0.options.stream.revision = revision
                }
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.create(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.CreateToStream {
    public struct Options: PersistentSubscriptionsCommonOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.Settings

        public init() {
            self.settings = .init()
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)
            }
        }
    }
}
