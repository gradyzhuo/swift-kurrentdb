//
//  PersistentSubscriptions.UpdateToAll.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/13.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct UpdateToAll: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        var group: String
        var options: Options

        init(group: String, options: Options) {
            self.group = group
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.groupName = group
            }
        }

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.update(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.UpdateToAll {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.Settings
        public var cursor: PositionCursor

        public init(settings: PersistentSubscription.Settings = .init(), from cursor: PositionCursor = .end) {
            self.settings = settings
            self.cursor = cursor
        }

        @discardableResult
        public func startFrom(_ cursor: PositionCursor) -> Self {
            withCopy { options in
                options.cursor = cursor
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)
                switch cursor {
                case .start:
                    $0.all.start = .init()
                case .end:
                    $0.all.end = .init()
                case let .position(commitPosition, preparePosition):
                    $0.all.position = .with {
                        $0.commitPosition = commitPosition
                        $0.preparePosition = preparePosition
                    }
                }
            }
        }
    }
}
