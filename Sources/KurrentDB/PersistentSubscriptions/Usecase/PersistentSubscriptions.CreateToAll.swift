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
        let options: Options

        public init(group: String, options: Options) {
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
        public func startFrom(position: PositionCursor) -> Self {
            withCopy { options in
                options.cursor = position
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

                if let filter {
                    $0.all.filter = .make(with: filter)
                } else {
                    $0.all.noFilter = .init()
                }
            }
        }
    }
}
