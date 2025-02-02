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
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        var groupName: String
        var options: Options

        init(groupName: String, options: Options) {
            self.groupName = groupName
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.groupName = groupName
            }
        }

        package func send(client: Client, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
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
        public var positionCursor: Cursor<StreamPosition>

        public init(settings: PersistentSubscription.Settings = .init(), positionCursor: Cursor<StreamPosition> = .end) {
            self.settings = settings
            self.positionCursor = positionCursor
        }

        @discardableResult
        public func startFrom(cursor: Cursor<StreamPosition>) -> Self {
            withCopy { options in
                options.positionCursor = cursor
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)
                switch positionCursor {
                case .start:
                    $0.all.start = .init()
                case .end:
                    $0.all.end = .init()
                case let .specified(pointer):
                    $0.all.position = .with {
                        $0.commitPosition = pointer.commit
                        $0.preparePosition = pointer.prepare
                    }
                }
            }
        }
    }
}
