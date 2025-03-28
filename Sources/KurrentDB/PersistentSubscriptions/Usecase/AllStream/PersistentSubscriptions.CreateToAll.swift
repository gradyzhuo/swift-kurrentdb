//
//  PersistentSubscriptions.CreateToAll.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/12.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct CreateToAll: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let group: String
        let cursor: PositionCursor
        let options: Options

        public init(group: String, cursor: PositionCursor, options: Options) {
            self.group = group
            self.cursor = cursor
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.groupName = group
                switch cursor {
                case .start:
                    $0.options.all.start = .init()
                case .end:
                    $0.options.all.end = .init()
                case let .position(commitPosition, preparePosition):
                    $0.options.all.position = .with {
                        $0.commitPosition = commitPosition
                        $0.preparePosition = preparePosition
                    }
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

extension PersistentSubscriptions.CreateToAll {
    public struct Options: PersistentSubscriptionsCommonOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.Settings
        public var filter: SubscriptionFilter?
        public var cursor: PositionCursor

        public init(settings: PersistentSubscription.Settings = .init(), filter: SubscriptionFilter? = nil, from cursor: PositionCursor = .end) {
            self.settings = settings
            self.filter = filter
            self.cursor = cursor
        }

        @discardableResult
        public func filter(_ value: SubscriptionFilter) -> Self {
            withCopy { $0.filter = filter }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)

                if let filter {
                    $0.all.filter = .make(with: filter)
                } else {
                    $0.all.noFilter = .init()
                }
            }
        }
    }
}
