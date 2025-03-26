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
        

        public private(set) var group: String
        public private(set) var cursor: PositionCursor
        public private(set) var options: Options

        init(group: String, cursor: PositionCursor = .start, options: Options) {
            self.group = group
            self.cursor = cursor
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
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
    public struct Options: PersistentSubscriptionsCommonOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        internal var settings: PersistentSubscription.Settings

        public init() {
            self.settings = .init()
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .from(settings: settings)
            }
        }
    }
}
