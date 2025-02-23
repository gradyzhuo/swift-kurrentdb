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
        var groupName: String
        var options: Options

        public init(streamIdentifier: StreamIdentifier, groupName: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.groupName = groupName
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = groupName
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
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
        public var revisionCursor: Cursor<StreamRevision>

        public init(settings: PersistentSubscription.Settings = .init(), revisionCursor: Cursor<StreamRevision> = .end) {
            self.settings = settings
            self.revisionCursor = revisionCursor
        }

        @discardableResult
        public func startFrom(revision: Cursor<StreamRevision>) -> Self {
            withCopy { options in
                options.revisionCursor = revision
            }
        }

        @discardableResult
        public mutating func set(consumerStrategy: PersistentSubscription.SystemConsumerStrategy) -> Self {
            withCopy { options in
                options.settings.consumerStrategy = consumerStrategy
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
